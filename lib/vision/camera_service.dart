import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

import 'burst.dart';

/// Owns the one camera the whole app uses.
///
/// Every mode asks this class for photos; none of them touches
/// [CameraController] directly. If the camera has to be opened differently
/// later (torch, resolution, front lens), it changes here and nowhere else.
class CameraService {
  CameraController? _controller;

  CameraController? get controller => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Opens the rear camera.
  ///
  /// Returns null on success, or a spoken sentence explaining the failure.
  /// The message is written to be spoken, not read.
  Future<String?> open() async {
    if (isReady) return null;

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        return 'Camera access is switched off for Cue. Open Settings, then '
            'Permissions, then Camera, and allow it.';
      }
      return 'Cue needs the camera to work. Press Capture again and allow '
          'camera access when the phone asks.';
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return 'No camera was found on this phone.';
      }

      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      _controller = controller;
      return null;
    } on CameraException catch (e) {
      final detail = e.description ?? e.code;
      return 'The camera could not start. $detail';
    } catch (_) {
      return 'The camera could not start. Close any other app that is using '
          'it, then try again.';
    }
  }

  /// Fires the ten-frame burst and returns the sharpest frames, best first.
  Future<List<BurstFrame>> burst({
    int shots = 10,
    int keep = 3,
    bool torch = false,
    void Function(int taken)? onProgress,
  }) async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return const [];

    if (torch) {
      try {
        await camera.setFlashMode(FlashMode.torch);
      } catch (_) {
        // Some devices refuse torch while previewing. Not fatal.
      }
    }

    try {
      return await captureBurst(
        camera,
        shots: shots,
        keep: keep,
        onProgress: onProgress,
      );
    } finally {
      if (torch) {
        try {
          await camera.setFlashMode(FlashMode.off);
        } catch (_) {
          // Ignore: the camera is being torn down anyway.
        }
      }
    }
  }

  Future<void> dispose() async {
    final camera = _controller;
    _controller = null;
    await camera?.dispose();
  }
}
