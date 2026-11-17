import 'package:cue/core/location_service.dart';
import 'package:cue/core/spoken_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('spoken time', () {
    test('morning with minutes', () {
      final time = DateTime(2026, 11, 10, 7, 5);
      expect(spokenTime(time, hindi: false), 'The time is 7:05 am.');
    });

    test('midday is twelve pm', () {
      final time = DateTime(2026, 11, 10, 12, 0);
      expect(spokenTime(time, hindi: false), 'The time is 12 pm.');
    });

    test('midnight is twelve am', () {
      final time = DateTime(2026, 11, 10, 0, 30);
      expect(spokenTime(time, hindi: false), 'The time is 12:30 am.');
    });

    test('evening', () {
      final time = DateTime(2026, 11, 10, 19, 45);
      expect(spokenTime(time, hindi: false), 'The time is 7:45 pm.');
    });

    test('Hindi time', () {
      final time = DateTime(2026, 11, 10, 7, 5);
      expect(spokenTime(time, hindi: true), 'अभी 7:05 बजे हैं।');
    });

    test('Hindi on the hour', () {
      final time = DateTime(2026, 11, 10, 9, 0);
      expect(spokenTime(time, hindi: true), 'अभी 9 बजे हैं।');
    });
  });

  group('spoken date', () {
    test('English date', () {
      final date = DateTime(2026, 11, 10);
      expect(
        spokenDate(date, hindi: false),
        'Today is Tuesday, 10 November 2026.',
      );
    });

    test('Hindi date', () {
      final date = DateTime(2026, 11, 10);
      expect(spokenDate(date, hindi: true), 'आज मंगलवार, 10 नवंबर 2026 है।');
    });

    test('Sunday is index zero-safe', () {
      final date = DateTime(2026, 11, 15);
      expect(spokenDate(date, hindi: false), contains('Sunday'));
    });
  });

  group('spoken location', () {
    test('a place name is used when there is one', () {
      const result = LocationResult(
        LocationFix(
          latitude: 26.9,
          longitude: 75.8,
          locality: 'Jaipur',
          city: 'Jaipur',
        ),
        LocationProblem.none,
      );
      expect(spokenLocation(result, hindi: false), 'You are in Jaipur.');
    });

    test('the wider place disambiguates', () {
      const result = LocationResult(
        LocationFix(
          latitude: 19.1,
          longitude: 72.8,
          locality: 'Andheri',
          city: 'Mumbai',
        ),
        LocationProblem.none,
      );
      expect(
        spokenLocation(result, hindi: false),
        'You are in Andheri, Mumbai.',
      );
    });

    test('an old fix is labelled as possibly out of date', () {
      const result = LocationResult(
        LocationFix(
          latitude: 26.9,
          longitude: 75.8,
          locality: 'Jaipur',
          city: 'Jaipur',
          age: Duration(days: 6),
        ),
        LocationProblem.none,
      );
      final text = spokenLocation(result, hindi: false);
      expect(text, contains('last known location'));
      expect(text, contains('may be out of date'));
      expect(text, contains('You are in Jaipur.'));
    });

    test('a fresh fix is stated without a warning', () {
      const result = LocationResult(
        LocationFix(
          latitude: 26.9,
          longitude: 75.8,
          locality: 'Jaipur',
          city: 'Jaipur',
          age: Duration(seconds: 4),
        ),
        LocationProblem.none,
      );
      expect(spokenLocation(result, hindi: false), 'You are in Jaipur.');
    });

    test('coordinates are spoken honestly when no place name exists', () {
      const result = LocationResult(
        LocationFix(latitude: 26.912, longitude: 75.787),
        LocationProblem.none,
      );
      final text = spokenLocation(result, hindi: false);
      expect(text, contains('Latitude 26.91 north'));
      expect(text, contains('longitude 75.79 east'));
    });

    test('southern and western coordinates say so', () {
      const result = LocationResult(
        LocationFix(latitude: -33.865, longitude: -70.6),
        LocationProblem.none,
      );
      final text = spokenLocation(result, hindi: false);
      expect(text, contains('south'));
      expect(text, contains('west'));
    });

    test('a refused permission explains where to fix it', () {
      const result = LocationResult(null, LocationProblem.permissionDenied);
      expect(
        spokenLocation(result, hindi: false),
        contains('Settings, then Permissions, then Location'),
      );
    });

    test('the phone-wide switch being off is named, not blamed on the sky', () {
      const result = LocationResult(null, LocationProblem.servicesOff);
      final text = spokenLocation(result, hindi: false);
      expect(text, contains('Location is off on your phone'));
      expect(text, contains('opening location settings'));
      expect(text, isNot(contains('window')));
    });

    test('a blocked permission says app settings are opening', () {
      const result = LocationResult(null, LocationProblem.permissionBlocked);
      expect(
        spokenLocation(result, hindi: false),
        contains('opening app settings'),
      );
    });

    test('no fix is not presented as a place', () {
      const result = LocationResult(null, LocationProblem.noFix);
      expect(spokenLocation(result, hindi: false), contains('could not'));
    });

    test('Hindi place sentence', () {
      const result = LocationResult(
        LocationFix(latitude: 26.9, longitude: 75.8, locality: 'जयपुर'),
        LocationProblem.none,
      );
      expect(spokenLocation(result, hindi: true), 'आप जयपुर में हैं।');
    });
  });

  group('spoken battery', () {
    test('the percentage is stated plainly', () {
      expect(spokenBattery(62, hindi: false), 'Battery is 62 percent.');
      expect(spokenBattery(62, hindi: true), 'बैटरी 62 प्रतिशत है।');
    });

    test('an unreadable level is admitted, not guessed', () {
      expect(spokenBattery(null, hindi: false), contains('could not'));
      expect(spokenBattery(-1, hindi: true), contains('नहीं मिली'));
    });
  });

  group('spoken reading progress', () {
    test('sentence number and how many are left', () {
      expect(
        spokenReadingProgress(index: 3, total: 12, hindi: false),
        'Sentence 3 of 12. 9 sentences left.',
      );
    });

    test('one left is singular', () {
      expect(
        spokenReadingProgress(index: 11, total: 12, hindi: false),
        'Sentence 11 of 12. One sentence left.',
      );
    });

    test('the last sentence says so instead of zero left', () {
      expect(
        spokenReadingProgress(index: 12, total: 12, hindi: false),
        contains('last sentence'),
      );
    });

    test('Hindi progress', () {
      expect(
        spokenReadingProgress(index: 3, total: 12, hindi: true),
        contains('वाक्य 3'),
      );
    });

    test('no reading is admitted', () {
      expect(
        spokenReadingProgress(index: 1, total: 0, hindi: false),
        'Nothing is being read yet.',
      );
    });
  });
}
