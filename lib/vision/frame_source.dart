import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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

  /// Raw bytes for the frame in the platform-native format, ready for ML Kit.
  ///
  /// On Android: NV21 (CameraX single plane, or converted from YUV420).
  /// On iOS: BGRA8888 single plane, passed straight through.
  /// No conversion is ever attempted on iOS — the camera is opened with
  /// `ImageFormatGroup.bgra8888` so the plugin hands over one plane directly.
  Uint8List get nv21 {
    final planes = image.planes;
    if (planes.isEmpty) return Uint8List(0);
    // iOS BGRA8888 always has a single plane; Android NV21 from CameraX does
    // too. The three-plane path is only reached on Android devices that ignore
    // the requested NV21 format and hand back raw YUV420.
    if (planes.length == 1) return planes.first.bytes;
    return _yuv420ToNv21(image);
  }

  /// Bytes-per-row for the first (and on iOS, only) plane.
  ///
  /// ML Kit needs this when constructing InputImageMetadata on iOS.
  int get bytesPerRow => image.planes.first.bytesPerRow;
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

/// Why the camera would not start.
///
/// The source does not choose the language: the live screen maps this to a
/// Hindi or English sentence.
enum CameraStartError {
  permissionDenied,
  permissionBlocked,
  noCamera,
  couldNotStart,
}

/// Supplies frames without the live screen knowing where they came from.
///
/// Section 8 of the specification asks for this boundary so an external
/// camera can be added later without rewriting the pipeline. Today the only
/// implementation is [PhoneCameraFrameSource].
abstract class FrameSource {
  Future<CameraStartError?> start({required FrameCallback onFrame});

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
  Future<CameraStartError?> start({required FrameCallback onFrame}) async {
    if (_running) return null;

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      return status.isPermanentlyDenied
          ? CameraStartError.permissionBlocked
          : CameraStartError.permissionDenied;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return CameraStartError.noCamera;

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
        // NV21 is Android-only. iOS outputs BGRA8888 from its camera pipeline.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
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
      if (kDebugMode) {
        debugPrint('camera: start failed ${error.code} ${error.description}');
      }
      return CameraStartError.couldNotStart;
    } catch (_) {
      await _tearDown();
      return CameraStartError.couldNotStart;
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
