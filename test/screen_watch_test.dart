import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:cue/live/screen_watch.dart';
import 'package:cue/vision/frame_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 720;
const _height = 480;

CameraFrame _frame(int Function(int x, int y) luma) {
  final pixels = Uint8List(_width * _height);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      pixels[y * _width + x] = luma(x, y);
    }
  }
  return CameraFrame(
    image: CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
        planes: [CameraImagePlane(bytes: pixels, bytesPerRow: _width)],
        height: _height,
        width: _width,
      ),
    ),
    description: const CameraDescription(
      name: 'test camera',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
    deviceOrientation: DeviceOrientation.portraitUp,
  );
}

CameraFrame _spinner(int phase) {
  const offsets = [
    (0, -14),
    (10, -10),
    (14, 0),
    (10, 10),
    (0, 14),
    (-10, 10),
    (-14, 0),
    (-10, -10),
  ];
  return _frame((x, y) {
    final dx = x - _width ~/ 2;
    final dy = y - _height ~/ 2;
    if (dx.abs() > 18 || dy.abs() > 18) return 25;
    for (var i = 0; i < offsets.length; i++) {
      final (sx, sy) = offsets[i];
      if ((dx - sx).abs() <= 3 && (dy - sy).abs() <= 3) {
        return 55 + ((i - phase) % 8) * 26;
      }
    }
    return 25;
  });
}

void main() {
  final start = DateTime(2026);
  DateTime at(int sample) => start.add(Duration(milliseconds: sample * 250));
  final spinner = List<CameraFrame>.generate(8, _spinner);

  test('reports movement from a spinner with no text', () {
    final watch = ScreenWatch();
    final notices = [
      for (var i = 0; i < 12; i++)
        watch.observe(
          spinner[i % spinner.length],
          at(i),
          phoneMoving: false,
          canAnnounce: true,
        ),
    ].whereType<ScreenWatchNotice>();
    expect(notices, [ScreenWatchNotice.movement]);
  });

  test('reports a still display once after an observed animation stops', () {
    final watch = ScreenWatch();
    final notices = [
      for (var i = 0; i < 72; i++)
        watch.observe(
          spinner[i < 8 ? i : 7],
          at(i),
          phoneMoving: false,
          canAnnounce: true,
        ),
    ].whereType<ScreenWatchNotice>();
    expect(notices, [ScreenWatchNotice.movement, ScreenWatchNotice.unchanged]);
  });

  test('exposure changes and display refresh bands do not count as motion', () {
    int panel(int x, int y) => (x ~/ 32 + y ~/ 32).isEven ? 55 : 120;
    final original = _frame(panel);
    final flicker = _frame(
      (x, y) => panel(x, y) + 20 + ((y ~/ 24).isEven ? 30 : 0),
    );
    final watch = ScreenWatch();
    final notices = [
      for (var i = 0; i < 65; i++)
        watch.observe(
          i.isEven ? original : flicker,
          at(i),
          phoneMoving: false,
          canAnnounce: true,
        ),
    ].whereType<ScreenWatchNotice>();
    expect(notices, [ScreenWatchNotice.unchanged]);
  });

  test('phone movement invalidates the stillness timer', () {
    final watch = ScreenWatch();
    final notices = [
      for (var i = 0; i < 70; i++)
        watch.observe(
          spinner.first,
          at(i),
          phoneMoving: i == 55,
          canAnnounce: true,
        ),
    ].whereType<ScreenWatchNotice>();
    expect(notices, isEmpty);
  });

  test('an unclear view produces an aiming hint without a stillness claim', () {
    final watch = ScreenWatch();
    final dark = _frame((_, _) => 20);
    final notices = [
      for (var i = 0; i < 70; i++)
        watch.observe(dark, at(i), phoneMoving: false, canAnnounce: true),
    ].whereType<ScreenWatchNotice>();
    expect(notices, [ScreenWatchNotice.unclear]);
  });
}
