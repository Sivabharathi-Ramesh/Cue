import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:cue/vision/camera_frame_encoder.dart';
import 'package:cue/vision/frame_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'crops the requested upright quadrant at every camera rotation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const width = 96;
      const height = 64;
      final bytes = Uint8List(width * height * 4);
      const quadrants = [
        [255, 0, 0],
        [0, 255, 0],
        [0, 0, 255],
        [255, 255, 0],
      ];
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final quadrant = (y < height ~/ 2 ? 0 : 2) + (x < width ~/ 2 ? 0 : 1);
          final [red, green, blue] = quadrants[quadrant];
          final index = (y * width + x) * 4;
          bytes.setRange(index, index + 4, [blue, green, red, 255]);
        }
      }
      final frame = CameraFrame(
        description: const CameraDescription(
          name: 'test camera',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        deviceOrientation: DeviceOrientation.portraitUp,
        image: CameraImage.fromPlatformInterface(
          CameraImageData(
            format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
            planes: [CameraImagePlane(bytes: bytes, bytesPerRow: width * 4)],
            height: height,
            width: width,
          ),
        ),
      );

      for (final (rotation, quadrant) in [
        (0, 0),
        (90, 2),
        (180, 3),
        (270, 1),
      ]) {
        final jpeg = await cameraFrameToJpeg(
          frame,
          rotation,
          region: const Rect.fromLTWH(0, 0, 0.5, 0.5),
        );
        final picture = img.decodeJpg(jpeg)!;
        final sideways = rotation % 180 != 0;
        expect(picture.width, sideways ? height ~/ 2 : width ~/ 2);
        expect(picture.height, sideways ? width ~/ 2 : height ~/ 2);
        final pixel = picture.getPixel(picture.width ~/ 2, picture.height ~/ 2);
        final [red, green, blue] = quadrants[quadrant];
        expect(pixel.r, closeTo(red, 4));
        expect(pixel.g, closeTo(green, 4));
        expect(pixel.b, closeTo(blue, 4));
      }
    },
  );
}
