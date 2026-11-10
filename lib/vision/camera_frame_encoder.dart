import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'frame_source.dart';

const MethodChannel _imageChannel = MethodChannel('cue/image');

/// Converts a camera frame into a JPEG the object detector can decode.
///
/// On Android the frame is handed to the phone's own YUV encoder, which
/// produces an upright, downscaled picture in a few milliseconds. Encoding the
/// same frame in Dart took seconds and made live object narration impossible.
/// iOS has no equivalent channel here, so it uses the Dart path.
Future<Uint8List> cameraFrameToJpeg(
  CameraFrame frame,
  int rotationDegrees,
) async {
  final image = frame.image;
  if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
    return Uint8List(0);
  }

  final width = image.width;
  final height = image.height;
  final planes = image.planes;
  final rowStride = planes.first.bytesPerRow;

  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final bytes = await _imageChannel.invokeMethod<Uint8List>(
        'nv21ToJpeg',
        <String, Object>{
          'bytes': planes.length == 1 ? planes.first.bytes : frame.nv21,
          'width': width,
          'height': height,
          'rowStride': planes.length == 1 ? rowStride : width,
          'rotation': rotationDegrees,
          // The detector letterboxes to 640x640; more pixels only cost time.
          'maxSide': 640,
          'quality': 82,
        },
      );
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (error) {
      // A platform channel that is missing or refuses the frame must not make
      // object mode blind; the slow Dart path below still works.
      if (kDebugMode) debugPrint('camera: native jpeg failed $error');
    }
  }

  img.Image picture;

  if (planes.length == 1) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      picture = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: planes.first.bytes.buffer,
        rowStride: rowStride,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
    } else {
      picture = _nv21ToImage(planes.first.bytes, width, height, rowStride);
    }
  } else if (planes.length == 3) {
    picture = _yuv420ToImage(image)!;
  } else {
    return Uint8List(0);
  }

  if (rotationDegrees != 0) {
    picture = img.copyRotate(picture, angle: rotationDegrees);
  }

  return Uint8List.fromList(img.encodeJpg(picture, quality: 78));
}

img.Image _nv21ToImage(Uint8List nv21, int width, int height, int rowStride) {
  final ySize = rowStride * height;
  final rgb = Uint8List(width * height * 3);
  var position = 0;

  for (var y = 0; y < height; y++) {
    final rowStart = y * rowStride;
    final uvRow = ySize + (y >> 1) * rowStride;

    for (var x = 0; x < width; x++) {
      final yPlane = nv21[rowStart + x];
      final uvOffset = uvRow + (x & ~1);
      final v = nv21[uvOffset] - 128;
      final u = nv21[uvOffset + 1] - 128;

      final r = yPlane + (1.402 * v).round();
      final g = yPlane - (0.344136 * u + 0.714136 * v).round();
      final b = yPlane + (1.772 * u).round();

      rgb[position++] = r.clamp(0, 255);
      rgb[position++] = g.clamp(0, 255);
      rgb[position++] = b.clamp(0, 255);
    }
  }

  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
}

/// Handles Android devices that ignore NV21 and return YUV420 instead.
img.Image? _yuv420ToImage(CameraImage image) {
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final width = image.width;
  final height = image.height;
  final rgb = Uint8List(width * height * 3);

  final yRowStride = yPlane.bytesPerRow;
  final yPixelStride = yPlane.bytesPerPixel ?? 1;
  final uRowStride = uPlane.bytesPerRow;
  final vRowStride = vPlane.bytesPerRow;
  final uPixelStride = uPlane.bytesPerPixel ?? 1;
  final vPixelStride = vPlane.bytesPerPixel ?? 1;

  var position = 0;
  for (var y = 0; y < height; y++) {
    final yRow = y * yRowStride;
    final uRow = (y >> 1) * uRowStride;
    final vRow = (y >> 1) * vRowStride;

    for (var x = 0; x < width; x++) {
      final uvOffset = (x >> 1);
      final yValue = yPlane.bytes[yRow + x * yPixelStride];
      final u = uPlane.bytes[uRow + uvOffset * uPixelStride] - 128;
      final v = vPlane.bytes[vRow + uvOffset * vPixelStride] - 128;

      final r = yValue + (1.402 * v).round();
      final g = yValue - (0.344136 * u + 0.714136 * v).round();
      final b = yValue + (1.772 * u).round();

      rgb[position++] = r.clamp(0, 255);
      rgb[position++] = g.clamp(0, 255);
      rgb[position++] = b.clamp(0, 255);
    }
  }

  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
}

/// Size of the upright frame, for callers that need it.
Size uprightSize(int width, int height, int rotationDegrees) =>
    rotationDegrees % 180 == 0
    ? Size(width.toDouble(), height.toDouble())
    : Size(height.toDouble(), width.toDouble());
