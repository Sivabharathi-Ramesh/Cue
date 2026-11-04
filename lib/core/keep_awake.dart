import 'package:flutter/services.dart';

/// Keeps the display awake while a reading session is live.
///
/// Android's display timeout is the biggest silent failure mode for a
/// hands-free reader: the screen locks, the app is backgrounded, and the camera
/// stops in the middle of a page. The flag is set on the activity window
/// through the same native channel that plays the tones, so no package is
/// needed and no permission is required.
///
/// This is not a wake lock in the battery sense: it only stops the *display*
/// from sleeping while the app is in front. When the session pauses or the app
/// closes, the flag is cleared.
class KeepAwake {
  KeepAwake._();

  static const MethodChannel _channel = MethodChannel('cue/feedback');

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepAwake', <String, dynamic>{
        'on': on,
      });
    } catch (_) {
      // No native channel (iOS today): the platform's own behaviour applies.
      // Failing to set a flag must never interrupt a reading.
    }
  }
}
