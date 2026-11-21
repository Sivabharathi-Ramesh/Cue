import AVFoundation
import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // A single engine is cheaper than starting one per tone.
  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var engineStarted = false
  private let personalVision = DispatchQueue(label: "cue.personal_items", qos: .userInitiated)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let personalItems = FlutterMethodChannel(name: "cue/personal_items", binaryMessenger: messenger)
    personalItems.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "personal_vision", message: nil, details: nil))
        return
      }
      self.describePersonalRegions(call, result: result)
    }
    let channel = FlutterMethodChannel(
      name: "cue/feedback",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "keepAwake" {
        let args = call.arguments as? [String: Any]
        let on = args?["on"] as? Bool ?? false
        // Used instead of FLAG_KEEP_SCREEN_ON. iOS releases it when the app
        // leaves the foreground, matching the Android flag's behaviour.
        UIApplication.shared.isIdleTimerDisabled = on
        result(nil)
        return
      }

      guard call.method == "tone",
        let args = call.arguments as? [String: Any],
        let frequency = args["frequency"] as? Double,
        let durationMs = args["durationMs"] as? Int,
        let volume = args["volume"] as? Double
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pan = args["pan"] as? Double ?? 0.0
      self?.playTone(
        frequency: frequency,
        durationMs: durationMs,
        volume: Float(volume),
        pan: Float(pan)
      )
      result(nil)
    }
  }

  private enum PersonalVisionError: Error { case image, region, output }

  private func describePersonalRegions(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "profileDirectory" {
      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        var directory = support.appendingPathComponent("CuePersonalItems", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        result(directory.path)
      } catch {
        result(FlutterError(code: "personal_storage", message: error.localizedDescription, details: nil))
      }
      return
    }
    guard call.method == "describe" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let jpeg = args["jpeg"] as? FlutterStandardTypedData,
      let regions = args["regions"] as? [[Double]],
      !regions.isEmpty
    else {
      result(FlutterError(code: "invalid_image", message: nil, details: nil))
      return
    }
    personalVision.async {
      do {
        guard let image = UIImage(data: jpeg.data)?.cgImage else { throw PersonalVisionError.image }
        let vectors = try regions.map { region -> FlutterStandardTypedData in
          guard region.count == 4, region.allSatisfy({ (0...1).contains($0) }) else {
            throw PersonalVisionError.region
          }
          let left = (region[0] * Double(image.width)).rounded()
          let top = (region[1] * Double(image.height)).rounded()
          let right = (region[2] * Double(image.width)).rounded()
          let bottom = (region[3] * Double(image.height)).rounded()
          let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
          guard !rect.isEmpty, let crop = image.cropping(to: rect) else { throw PersonalVisionError.region }
          let request = VNGenerateImageFeaturePrintRequest()
          request.revision = VNGenerateImageFeaturePrintRequestRevision1
          request.imageCropAndScaleOption = .scaleFill
          try VNImageRequestHandler(cgImage: crop).perform([request])
          guard let observation = request.results?.first else { throw PersonalVisionError.output }
          switch observation.elementType {
          case .float: return FlutterStandardTypedData(float32: observation.data)
          case .double: return FlutterStandardTypedData(float64: observation.data)
          default: throw PersonalVisionError.output
          }
        }
        DispatchQueue.main.async { result(["format": "vision-feature-print-v1", "vectors": vectors]) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "personal_vision", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: – Tone synthesis

  private func playTone(
    frequency: Double, durationMs: Int, volume: Float, pan: Float
  ) {
    let sampleRate: Double = 44100
    let frameCount = AVAudioFrameCount(sampleRate * Double(durationMs) / 1000.0)
    guard frameCount > 0 else { return }

    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: AVAudioFormat(
          standardFormatWithSampleRate: sampleRate, channels: 2)!,
        frameCapacity: frameCount)
    else { return }

    buffer.frameLength = frameCount

    // Build a sine wave with a short linear fade-in and fade-out to avoid
    // clicks — the same technique the Android AudioTrack channel uses.
    let fadeFrames = min(Int(sampleRate * 0.005), Int(frameCount) / 4)
    let leftGain = volume * max(0, min(1, 1 - pan))
    let rightGain = volume * max(0, min(1, 1 + pan))
    let leftData = buffer.floatChannelData![0]
    let rightData = buffer.floatChannelData![1]

    for i in 0..<Int(frameCount) {
      let sample = Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))

      // Linear fade in/out envelope.
      var envelope: Float = 1.0
      if i < fadeFrames {
        envelope = Float(i) / Float(fadeFrames)
      } else if i >= Int(frameCount) - fadeFrames {
        envelope = Float(Int(frameCount) - 1 - i) / Float(fadeFrames)
      }

      leftData[i] = sample * leftGain * envelope
      rightData[i] = sample * rightGain * envelope
    }

    startEngineIfNeeded()
    playerNode.scheduleBuffer(buffer, completionHandler: nil)
    if !playerNode.isPlaying { playerNode.play() }
  }

  private func startEngineIfNeeded() {
    guard !engineStarted else { return }
    audioEngine.attach(playerNode)
    audioEngine.connect(
      playerNode,
      to: audioEngine.mainMixerNode,
      format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
    )
    // Match the TTS audio session: playback + voicePrompt + mixWithOthers.
    // Leaving mode at .default would downgrade the shared session and silence
    // the reading voice on every tone.
    try? AVAudioSession.sharedInstance().setCategory(
      .playback,
      mode: .voicePrompt,
      options: [.mixWithOthers]
    )
    try? AVAudioSession.sharedInstance().setActive(true)
    try? audioEngine.start()
    engineStarted = true
  }
}
