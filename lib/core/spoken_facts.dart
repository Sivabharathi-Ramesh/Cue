import 'location_service.dart';

/// Sentences for facts the phone knows without looking at anything.
///
/// Time, date and place are the questions a blind user asks most often, and
/// none of them need the camera. Keeping the wording here means the answer is
/// identical whether it was asked by voice or by gesture, and can be tested
/// without a phone, a clock or a satellite.

const List<String> _hindiWeekdays = <String>[
  'सोमवार',
  'मंगलवार',
  'बुधवार',
  'गुरुवार',
  'शुक्रवार',
  'शनिवार',
  'रविवार',
];

const List<String> _englishWeekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _hindiMonths = <String>[
  'जनवरी',
  'फ़रवरी',
  'मार्च',
  'अप्रैल',
  'मई',
  'जून',
  'जुलाई',
  'अगस्त',
  'सितंबर',
  'अक्टूबर',
  'नवंबर',
  'दिसंबर',
];

const List<String> _englishMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "The time is 7:05 pm." / "अभी 7:05 बजे हैं।"
///
/// A 12-hour clock with am/pm is what most people in India read aloud. Minutes
/// are zero-padded so "7:05" is not spoken as "7 5".
String spokenTime(DateTime now, {required bool hindi}) {
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final minutes = now.minute.toString().padLeft(2, '0');

  if (hindi) {
    if (now.minute == 0) return 'अभी $hour12 बजे हैं।';
    return 'अभी $hour12:$minutes बजे हैं।';
  }

  final period = now.hour < 12 ? 'am' : 'pm';
  if (now.minute == 0) return 'The time is $hour12 $period.';
  return 'The time is $hour12:$minutes $period.';
}

/// "Today is Tuesday, 10 November 2026."
String spokenDate(DateTime now, {required bool hindi}) {
  // DateTime.weekday is 1 (Monday) to 7 (Sunday).
  final weekdayIndex = now.weekday - 1;
  final monthIndex = now.month - 1;

  if (hindi) {
    final weekday = _hindiWeekdays[weekdayIndex];
    final month = _hindiMonths[monthIndex];
    return 'आज $weekday, ${now.day} $month ${now.year} है।';
  }

  final weekday = _englishWeekdays[weekdayIndex];
  final month = _englishMonths[monthIndex];
  return 'Today is $weekday, ${now.day} $month ${now.year}.';
}

/// The spoken answer to "where am I?".
///
/// A place name is preferred; coordinates are the fallback because they are
/// still true. Cue never invents an address.
String spokenLocation(LocationResult result, {required bool hindi}) {
  switch (result.problem) {
    case LocationProblem.servicesOff:
      return hindi
          ? 'फ़ोन की लोकेशन बंद है। मैं लोकेशन सेटिंग खोल रहा हूँ। लोकेशन चालू करें, '
                'फिर दोबारा पूछें।'
          : 'Location is off on your phone. I am opening location settings. '
                'Turn Location on, then ask again.';
    case LocationProblem.permissionDenied:
      return hindi
          ? 'लोकेशन की अनुमति बंद है। सेटिंग, अनुमतियाँ, लोकेशन में जाकर क्यू को '
                'अनुमति दें।'
          : 'Location access is off. Open Settings, then Permissions, then '
                'Location, and allow Cue.';
    case LocationProblem.permissionBlocked:
      return hindi
          ? 'क्यू के लिए लोकेशन अनुमति बंद है। मैं ऐप सेटिंग खोल रहा हूँ। लोकेशन की '
                'अनुमति दें, फिर दोबारा पूछें।'
          : 'Location permission is off for Cue. I am opening app settings. '
                'Allow Location, then ask again.';
    case LocationProblem.noFix:
      return hindi
          ? 'अभी लोकेशन नहीं मिली। खुले में या खिड़की के पास जाकर फिर पूछें।'
          : 'I could not get a location fix. Move near a window or outside, '
                'then ask again.';
    case LocationProblem.none:
      final fix = result.fix;
      if (fix == null) {
        return hindi
            ? 'अभी लोकेशन नहीं मिली।'
            : 'I could not get a location just now.';
      }
      return fix.hasPlaceName
          ? _placeSentence(fix, hindi: hindi)
          : _coordinateSentence(fix, hindi: hindi);
  }
}

String _placeSentence(LocationFix fix, {required bool hindi}) {
  final place = fix.placeName!;
  final wider = fix.widerPlaceName;

  if (hindi) {
    return wider == null ? 'आप $place में हैं।' : 'आप $place, $wider में हैं।';
  }
  return wider == null ? 'You are in $place.' : 'You are in $place, $wider.';
}

String _coordinateSentence(LocationFix fix, {required bool hindi}) {
  final north = fix.latitude >= 0;
  final east = fix.longitude >= 0;
  final lat = fix.latitude.abs().toStringAsFixed(2);
  final lon = fix.longitude.abs().toStringAsFixed(2);

  if (hindi) {
    return 'जगह का नाम नहीं मिला। अक्षांश $lat ${north ? 'उत्तर' : 'दक्षिण'}, '
        'देशांतर $lon ${east ? 'पूर्व' : 'पश्चिम'}।';
  }
  return 'I have your position but no place name. Latitude $lat '
      '${north ? 'north' : 'south'}, longitude $lon ${east ? 'east' : 'west'}.';
}
