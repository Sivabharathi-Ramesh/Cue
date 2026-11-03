import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'burst.dart';

/// Owns the one camera the whole app uses.
///
/// Every mode asks this class for photos; none of them touches
/// [CameraController] directly. If the camera has to be opened differently
/// later (torch, resolution, front lens), it changes here and nowhere else.
class CameraService {
  CameraController? _controller;

  /// The burst currently holding the camera stream, if any.
  Future<List<BurstFrame>>? _burstInFlight;

  /// An open() already in progress, so a lifecycle bounce (the permission
  /// dialog, the notification shade) cannot start a second camera.
  Future<String?>? _opening;

  /// A dispose() still running; open() waits for it.
  Future<void>? _disposing;

  CameraController? get controller => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Opens the rear camera.
  ///
  /// Returns null on success, or a spoken sentence explaining the failure.
  /// The message is written to be spoken, not read.
  Future<String?> open() async {
    if (isReady) return null;

    final alreadyOpening = _opening;
    if (alreadyOpening != null) return alreadyOpening;

    final opening = _open();
    _opening = opening;
    try {
      return await opening;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<String?> _open() async {
    final disposing = _disposing;
    if (disposing != null) {
      try {
        await disposing;
      } catch (_) {
        // The old camera is on its way out. Carry on and open a fresh one.
      }
    }

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
        // 720p is enough to read a page that fills the frame, and it is the
        // resolution the live stream is sampled at too.
        ResolutionPreset.medium,
        enableAudio: false,
        // NV21 is what Android hands over from its own image analysis
        // pipeline, with no JPEG encoding in between. That is what makes a
        // ten-frame burst take about a second instead of twenty.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      // Keep FocusMode.auto pinned rather than relying on the default, which
      // differs between devices and can leave a page permanently soft.
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Not every camera exposes focus control. Ignore.
      }

      await controller.setFlashMode(FlashMode.off);

      _controller = controller;
      debugPrint(
        'camera: sensorOrientation=${rear.sensorOrientation} '
        'lens=${rear.lensDirection.name} '
        'preview=${controller.value.previewSize}',
      );
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
  ///
  /// [isCancelled] lets a caller abandon a burst (the user pressed Stop).
  /// Only one burst runs at a time: a second call waits for the first to
  /// release the camera stream rather than failing and falling back to the
  /// slow still-capture path.
  Future<List<BurstFrame>> burst({
    int shots = 10,
    int keep = 3,
    bool torch = false,
    void Function(int taken)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return const [];

    final previous = _burstInFlight;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // The earlier burst failed; that is its caller's problem.
      }
    }

    final running = _runBurst(
      camera,
      shots: shots,
      keep: keep,
      torch: torch,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    _burstInFlight = running;

    try {
      return await running;
    } finally {
      if (identical(_burstInFlight, running)) _burstInFlight = null;
    }
  }

  Future<List<BurstFrame>> _runBurst(
    CameraController camera, {
    required int shots,
    required int keep,
    required bool torch,
    required void Function(int taken)? onProgress,
    required bool Function()? isCancelled,
  }) async {
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
        isCancelled: isCancelled,
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

    if (camera == null) {
      final pending = _disposing;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // Already gone.
        }
      }
      return;
    }

    final disposing = camera.dispose();
    _disposing = disposing;
    try {
      await disposing;
    } finally {
      if (identical(_disposing, disposing)) _disposing = null;
    }
  }
}
