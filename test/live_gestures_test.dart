import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:cue/core/audio_bus.dart';
import 'package:cue/live/live_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tts = MethodChannel('flutter_tts');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const storage = MethodChannel('plugins.flutter.io/path_provider');
  const sensorPrefix = 'dev.fluttercommunity.plus/sensors';
  const acceleration = MethodChannel('$sensorPrefix/accelerometer');
  const mockStreams = [
    MethodChannel('cue/sensors'),
    MethodChannel('$sensorPrefix/method'),
    MethodChannel('$sensorPrefix/gyroscope'),
    acceleration,
  ];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final spoken = <String>[];
  var stops = 0;

  setUp(() {
    spoken.clear();
    stops = 0;
    messenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method == 'isLanguageAvailable') return true;
      if (call.method == 'getVoices') return [];
      if (call.method == 'stop') stops++;
      if (call.method == 'speak') {
        final argument = call.arguments;
        spoken.add((argument is Map ? argument['text'] : argument) as String);
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(permissions, (call) async {
      final requested = (call.arguments as List).cast<int>();
      return {for (final permission in requested) permission: 0};
    });
    messenger.setMockMethodCallHandler(storage, (_) async => null);
    for (final channel in mockStreams) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() async {
    AudioBus.instance.unmute();
    await AudioBus.instance.stop();
    AudioBus.instance.forgetLastResult();
    for (final channel in [tts, permissions, storage, ...mockStreams]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> openCue(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(home: LiveScreen()));
    await tester.pumpAndSettle();
    spoken.clear();
  }

  Future<void> slowSwipe(WidgetTester tester, Offset step) async {
    final touch = await tester.startGesture(const Offset(220, 260));
    for (var i = 1; i <= 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await touch.moveBy(step, timeStamp: Duration(milliseconds: 100 * i));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await touch.up(timeStamp: const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('Help retries and slow swipes work on the live screen', (
    tester,
  ) async {
    await openCue(tester);
    final camera = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.customSemanticsActions?.keys.any(
                (action) => action.label == 'Help',
              ) ==
              true,
    );
    expect(
      tester
          .getSemantics(camera)
          .getSemanticsData()
          .hasAction(SemanticsAction.longPress),
      isTrue,
    );

    final start = DateTime.utc(2026, 11, 23).microsecondsSinceEpoch;
    const codec = StandardMethodCodec();
    Future<void> shake(int startingMs) async {
      for (var milliseconds = 0; milliseconds <= 760; milliseconds += 20) {
        final x = 6.8 * math.sin(2 * math.pi * milliseconds / 380);
        await messenger.handlePlatformMessage(
          acceleration.name,
          codec.encodeSuccessEnvelope([
            x,
            -9.81,
            0.0,
            (start + (startingMs + milliseconds) * 1000).toDouble(),
          ]),
          null,
        );
      }
      await tester.pumpAndSettle();
    }

    AudioBus.instance.mute();
    await shake(0);
    expect(spoken, isEmpty);

    AudioBus.instance.unmute();
    await shake(900);
    expect(spoken, [startsWith('Controls.')]);

    spoken.clear();
    await slowSwipe(tester, const Offset(30, 0));
    expect(spoken, [startsWith('Object mode.')]);
    final answer = spoken.single;
    await slowSwipe(tester, const Offset(0, 30));
    expect(spoken, [answer, answer]);

    final stopsBeforeSwipe = stops;
    await slowSwipe(tester, const Offset(0, -30));
    expect(stops, greaterThan(stopsBeforeSwipe));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
