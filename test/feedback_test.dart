import 'package:cue/core/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const feedback = MethodChannel('cue/feedback');
  const vibration = MethodChannel('vibration');

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'item confirmation plays its signature once on ${platform.name}',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        messenger.setMockMethodCallHandler(feedback, (_) async => null);
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(vibration, (call) async {
          if (call.method == 'hasCustomVibrationsSupport') return true;
          calls.add(call);
          return null;
        });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = previousPlatform;
          messenger.setMockMethodCallHandler(feedback, null);
          messenger.setMockMethodCallHandler(vibration, null);
        });

        await Feedback.instance.itemFound();

        final call = calls.single;
        expect(call.method, 'vibrate');
        expect(call.arguments['pattern'], [0, 60, 75, 60, 100, 170]);
        expect(call.arguments['intensities'], [0, 170, 0, 170, 0, 240]);
        expect(call.arguments['repeat'], -1);
      },
    );
  }
}
