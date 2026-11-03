import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// One frame handed to the analysis pipeline.
///
/// Holds the raw camera image plus everything needed to interpret it: which
/// lens produced it, and how the phone was held at the time.
class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.description,
    required this.deviceOrientation,
  });

  final CameraImage image;
  final CameraDescription description;
  final DeviceOrientation deviceOrientation;

  /// The frame as NV21 bytes, ready for ML Kit.
  ///
  /// CameraX can produce NV21 directly when the controller is created with
  /// `ImageFormatGroup.nv21`. In that case the plugin hands over one plane and
  /// no conversion is needed. The three-plane YUV path is kept as a fallback
  /// for devices or platforms that ignore the requested format.
  Uint8List get nv21 {
    final planes = image.planes;
    if (planes.isEmpty) return Uint8List(0);
    if (planes.length == 1) return planes.first.bytes;
    return _yuv420ToNv21(image);
  }
}

Uint8List _yuv420ToNv21(CameraImage image) {
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final width = image.width;
  final height = image.height;
  final output = Uint8List(width * height * 3 ~/ 2);

  final yRowStride = yPlane.bytesPerRow;
  final yPixelStride = yPlane.bytesPerPixel ?? 1;
  var position = 0;

  for (var row = 0; row < height; row++) {
    final rowStart = row * yRowStride;
    for (var col = 0; col < width; col++) {
      output[position++] = yPlane.bytes[rowStart + col * yPixelStride];
    }
  }

  final uRowStride = uPlane.bytesPerRow;
  final vRowStride = vPlane.bytesPerRow;
  final uPixelStride = uPlane.bytesPerPixel ?? 1;
  final vPixelStride = vPlane.bytesPerPixel ?? 1;

  for (var row = 0; row < height ~/ 2; row++) {
    final uRowStart = row * uRowStride;
    final vRowStart = row * vRowStride;
    for (var col = 0; col < width ~/ 2; col++) {
      // NV21 is V then U.
      output[position++] = vPlane.bytes[vRowStart + col * vPixelStride];
      output[position++] = uPlane.bytes[uRowStart + col * uPixelStride];
    }
  }

  return output;
}

typedef FrameCallback = void Function(CameraFrame frame);

/// Supplies frames without the live screen knowing where they came from.
///
/// Section 8 of the specification asks for this boundary so an external
/// camera can be added later without rewriting the pipeline. Today the only
/// implementation is [PhoneCameraFrameSource].
abstract class FrameSource {
  Future<String?> start({required FrameCallback onFrame});

  Future<void> stop();

  Future<void> dispose() => stop();

  bool get isRunning;

  CameraController? get controller;

  Future<void> setTorch(bool on) async {
    // Optional by default: a source without a torch simply ignores this.
  }
}

/// The phone's rear camera, streamed at a resolution OCR can use.
class PhoneCameraFrameSource extends FrameSource {
  CameraController? _controller;
  bool _running = false;

  @override
  CameraController? get controller => _controller;

  @override
  bool get isRunning => _running;

  @override
  Future<String?> start({required FrameCallback onFrame}) async {
    if (_running) return null;

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        return 'Camera access is switched off for Cue. Open Settings, then '
            'Permissions, then Camera, and allow it.';
      }
      return 'Cue needs the camera to work. Double tap to try again and allow '
          'camera access when the phone asks.';
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return 'No camera was found on this phone.';

      final rear = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rear,
        // 720p is the smallest stream that still resolves printed body text
        // at arm's length. 480p was legible only for headings in testing.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      _controller = controller;
      await controller.startImageStream((image) {
        onFrame(
          CameraFrame(
            image: image,
            description: rear,
            deviceOrientation: controller.value.deviceOrientation,
          ),
        );
      });
      _running = true;
      return null;
    } on CameraException catch (error) {
      await _tearDown();
      final detail = error.description ?? error.code;
      return 'The camera could not start. $detail';
    } catch (_) {
      await _tearDown();
      return 'The camera could not start. Close any other app that is using '
          'it, then double tap to try again.';
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _tearDown();
  }

  @override
  Future<void> setTorch(bool on) async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;
    try {
      await camera.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      // Some devices refuse torch while previewing. Not fatal.
    }
  }

  Future<void> _tearDown() async {
    final camera = _controller;
    _controller = null;
    if (camera == null) return;

    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (_) {
      // The stream may already be gone with the activity.
    }

    try {
      await camera.dispose();
    } catch (_) {
      // Double dispose is safe to ignore.
    }
  }
}
