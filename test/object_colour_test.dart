import 'dart:typed_data';
import 'dart:ui';

import 'package:cue/vision/object_colour.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a square RGBA image filled with one colour.
Uint8List solid(int size, int r, int g, int b) {
  final data = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    data[i * 4] = r;
    data[i * 4 + 1] = g;
    data[i * 4 + 2] = b;
    data[i * 4 + 3] = 255;
  }
  return data;
}

void main() {
  const box = Rect.fromLTWH(0, 0, 1, 1);
  const half = Rect.fromLTWH(0.25, 0.25, 0.5, 0.5);

  group('colour naming', () {
    test('a red object is red', () {
      final reading = dominantColourInBox(solid(32, 200, 30, 30), 32, 32, box);
      expect(reading, isNotNull);
      expect(reading!.colour, ObjectColour.red);
      expect(englishColourName(reading), 'red');
    });

    test('a blue object is blue', () {
      final reading = dominantColourInBox(solid(32, 20, 60, 200), 32, 32, box);
      expect(reading!.colour, ObjectColour.blue);
    });

    test('a dark blue object keeps its shade', () {
      final reading = dominantColourInBox(solid(32, 10, 20, 90), 32, 32, box);
      expect(reading!.colour, ObjectColour.blue);
      expect(reading.dark, isTrue);
      expect(englishColourName(reading), 'dark blue');
    });

    test('white paper is white', () {
      final reading = dominantColourInBox(
        solid(32, 245, 245, 243),
        32,
        32,
        box,
      );
      expect(reading!.colour, ObjectColour.white);
    });

    test('a dark object is black', () {
      final reading = dominantColourInBox(solid(32, 15, 15, 17), 32, 32, box);
      expect(reading!.colour, ObjectColour.black);
    });

    test('a mid grey object is grey', () {
      final reading = dominantColourInBox(
        solid(32, 128, 128, 128),
        32,
        32,
        box,
      );
      expect(reading!.colour, ObjectColour.grey);
    });

    test('a dull yellow-green is green', () {
      final reading = dominantColourInBox(solid(32, 120, 180, 60), 32, 32, box);
      expect(reading!.colour, ObjectColour.green);
    });

    test('dark orange wood is brown', () {
      final reading = dominantColourInBox(solid(32, 110, 70, 25), 32, 32, box);
      expect(reading!.colour, ObjectColour.brown);
    });

    test('the middle of the box decides, not its edge', () {
      // White background with a red square in the middle. The inset sampling
      // must ignore the border.
      const size = 40;
      final data = solid(size, 250, 250, 250);
      for (var y = 12; y < 28; y++) {
        for (var x = 12; x < 28; x++) {
          final index = (y * size + x) * 4;
          data[index] = 190;
          data[index + 1] = 20;
          data[index + 2] = 20;
        }
      }

      final reading = dominantColourInBox(data, size, size, box);
      expect(reading!.colour, ObjectColour.red);
    });

    test('a box entirely outside the image returns nothing', () {
      final reading = dominantColourInBox(
        solid(32, 200, 30, 30),
        32,
        32,
        const Rect.fromLTWH(2, 2, 1, 1),
      );
      expect(reading, isNull);
    });

    test('a tiny box returns nothing rather than guessing', () {
      final reading = dominantColourInBox(
        solid(32, 200, 30, 30),
        32,
        32,
        const Rect.fromLTWH(0.5, 0.5, 0.01, 0.01),
      );
      expect(reading, isNull);
    });

    test('a partial box is still sampled', () {
      final reading = dominantColourInBox(solid(32, 200, 30, 30), 32, 32, half);
      expect(reading!.colour, ObjectColour.red);
    });

    test('Hindi names follow the colour', () {
      const reading = ColourReading(ObjectColour.red);
      expect(hindiColourName(reading), 'लाल');
      expect(
        hindiColourName(const ColourReading(ObjectColour.blue, dark: true)),
        'गहरा नीला',
      );
    });
  });
}
