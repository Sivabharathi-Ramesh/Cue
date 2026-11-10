import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// The colour families Cue is willing to name.
///
/// Deliberately small. "Crimson" and "chartreuse" are not useful to someone who
/// cannot see the object, and a detector that says them is pretending to a
/// precision the pixels do not support.
enum ObjectColour {
  black,
  white,
  grey,
  red,
  orange,
  yellow,
  green,
  teal,
  blue,
  purple,
  pink,
  brown,
}

/// A named colour with the shade Cue saw.
///
/// [dark] and [light] are only set for colours where the shade changes what the
/// user would picture: "dark blue" is a different object from "light blue",
/// but "black" and "white" already carry their own lightness.
class ColourReading {
  const ColourReading(this.colour, {this.dark = false, this.light = false});

  final ObjectColour colour;
  final bool dark;
  final bool light;

  @override
  bool operator ==(Object other) =>
      other is ColourReading &&
      other.colour == colour &&
      other.dark == dark &&
      other.light == light;

  @override
  int get hashCode => Object.hash(colour, dark, light);

  @override
  String toString() =>
      'ColourReading(${colour.name}${dark ? ', dark' : ''}'
      '${light ? ', light' : ''})';
}

/// Samples the middle of [box] and names the colour it finds.
///
/// [rgba] is a tightly packed RGBA buffer of [width] x [height] pixels, the
/// format `ui.Image.toByteData` produces. [box] is in normalised coordinates
/// (0-1) like the detector's own boxes.
///
/// The middle 70% of the box is used on purpose: box edges almost always
/// include background, and a table behind a red mug would otherwise turn the
/// mug brown. Near-white highlights and near-black shadows are ignored when
/// there is enough mid-tone colour left, so a shiny bottle keeps its own hue
/// instead of becoming "white".
ColourReading? dominantColourInBox(
  Uint8List rgba,
  int width,
  int height,
  Rect box,
) {
  if (width <= 0 || height <= 0) return null;
  if (rgba.length < width * height * 4) return null;
  if (!box.width.isFinite || !box.height.isFinite) return null;

  final left = (box.left * width).clamp(0, width - 1).toDouble();
  final right = (box.right * width).clamp(0, width - 1).toDouble();
  final top = (box.top * height).clamp(0, height - 1).toDouble();
  final bottom = (box.bottom * height).clamp(0, height - 1).toDouble();

  final boxWidth = right - left;
  final boxHeight = bottom - top;
  if (boxWidth < 3 || boxHeight < 3) return null;

  // Inset by 15% on each side; see the doc comment.
  final x0 = (left + boxWidth * 0.15).round();
  final x1 = (right - boxWidth * 0.15).round();
  final y0 = (top + boxHeight * 0.15).round();
  final y1 = (bottom - boxHeight * 0.15).round();
  if (x1 - x0 < 2 || y1 - y0 < 2) return null;

  final stepX = math.max(1, (x1 - x0) ~/ 18);
  final stepY = math.max(1, (y1 - y0) ~/ 18);

  // Hue histogram: 12 buckets of 30 degrees.
  final hueBucket = List<int>.filled(12, 0);
  var samples = 0;
  var saturated = 0;
  var satHueX = 0.0;
  var satHueY = 0.0;
  var satLightness = 0.0;
  var allLightness = 0.0;
  var allSaturation = 0.0;

  for (var y = y0; y <= y1; y += stepY) {
    for (var x = x0; x <= x1; x += stepX) {
      final index = (y * width + x) * 4;
      if (index + 3 >= rgba.length) continue;
      final alpha = rgba[index + 3];
      if (alpha < 128) continue;

      final r = rgba[index] / 255.0;
      final g = rgba[index + 1] / 255.0;
      final b = rgba[index + 2] / 255.0;

      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final delta = maxC - minC;
      final lightness = (maxC + minC) / 2;
      final saturation = maxC <= 0 ? 0.0 : delta / maxC;

      samples++;
      allLightness += lightness;
      allSaturation += saturation;

      // Punch-through highlights and deep shadow say nothing about the paint
      // or plastic the object is made of.
      final isHighlight = lightness > 0.93 && saturation < 0.25;
      final isShadow = lightness < 0.09;
      if (isHighlight || isShadow) continue;

      if (saturation >= 0.18) {
        final hue = _hue(r, g, b, maxC, delta);
        final bucket = ((hue / 30).floor()) % 12;
        hueBucket[bucket]++;
        saturated++;
        // Weight the mean hue by saturation: a faint tint should not drag a
        // strong colour off its true name.
        final angle = hue * math.pi / 180.0;
        satHueX += math.cos(angle) * saturation;
        satHueY += math.sin(angle) * saturation;
        satLightness += lightness;
      }
    }
  }

  if (samples == 0) return null;

  final meanLightness = allLightness / samples;
  final meanSaturation = allSaturation / samples;

  // Almost no colour anywhere: black, white or grey by brightness alone.
  if (saturated < samples * 0.12 || meanSaturation < 0.12) {
    return ColourReading(_achromaticName(meanLightness));
  }

  final hue = _circularMeanHue(satHueX, satHueY);
  final shadeLightness = satLightness / saturated;

  // A dark orange-red is brown, and that is what people call wood, leather and
  // cardboard.
  if (hue >= 12 && hue < 48 && shadeLightness < 0.45) {
    return const ColourReading(ObjectColour.brown);
  }

  final colour = _hueName(hue);
  if (colour == ObjectColour.black || colour == ObjectColour.white) {
    return ColourReading(colour);
  }

  // "Dark black" and "light white" are nonsense; the shade words only apply to
  // real hues.
  return ColourReading(
    colour,
    dark: shadeLightness < 0.28,
    light: shadeLightness > 0.72,
  );
}

/// English phrase for a reading: "dark blue", "grey", "red".
String englishColourName(ColourReading reading) {
  final base = switch (reading.colour) {
    ObjectColour.black => 'black',
    ObjectColour.white => 'white',
    ObjectColour.grey => 'grey',
    ObjectColour.red => 'red',
    ObjectColour.orange => 'orange',
    ObjectColour.yellow => 'yellow',
    ObjectColour.green => 'green',
    ObjectColour.teal => 'green-blue',
    ObjectColour.blue => 'blue',
    ObjectColour.purple => 'purple',
    ObjectColour.pink => 'pink',
    ObjectColour.brown => 'brown',
  };
  if (reading.dark) return 'dark $base';
  if (reading.light) return 'light $base';
  return base;
}

/// Hindi phrase for a reading, with the adjective before the noun.
String hindiColourName(ColourReading reading) {
  final base = switch (reading.colour) {
    ObjectColour.black => 'काला',
    ObjectColour.white => 'सफ़ेद',
    ObjectColour.grey => 'धूसर',
    ObjectColour.red => 'लाल',
    ObjectColour.orange => 'नारंगी',
    ObjectColour.yellow => 'पीला',
    ObjectColour.green => 'हरा',
    ObjectColour.teal => 'हरा-नीला',
    ObjectColour.blue => 'नीला',
    ObjectColour.purple => 'बैंगनी',
    ObjectColour.pink => 'गुलाबी',
    ObjectColour.brown => 'भूरा',
  };
  if (reading.dark) return 'गहरा $base';
  if (reading.light) return 'हल्का $base';
  return base;
}

ObjectColour _achromaticName(double lightness) {
  if (lightness < 0.18) return ObjectColour.black;
  if (lightness > 0.85) return ObjectColour.white;
  if (lightness < 0.38) return ObjectColour.black;
  if (lightness < 0.62) return ObjectColour.grey;
  return ObjectColour.grey;
}

double _hue(double r, double g, double b, double maxC, double delta) {
  if (delta == 0) return 0;
  double hue;
  if (maxC == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (maxC == g) {
    hue = 60 * ((b - r) / delta + 2);
  } else {
    hue = 60 * ((r - g) / delta + 4);
  }
  if (hue < 0) hue += 360;
  return hue;
}

double _circularMeanHue(double x, double y) {
  if (x == 0 && y == 0) return 0;
  final angle = math.atan2(y, x);
  var degrees = angle * 180 / math.pi;
  if (degrees < 0) degrees += 360;
  return degrees;
}

ObjectColour _hueName(double hue) {
  if (hue < 15 || hue >= 345) return ObjectColour.red;
  if (hue < 40) return ObjectColour.orange;
  if (hue < 65) return ObjectColour.yellow;
  if (hue < 150) return ObjectColour.green;
  if (hue < 190) return ObjectColour.teal;
  if (hue < 255) return ObjectColour.blue;
  if (hue < 290) return ObjectColour.purple;
  return ObjectColour.pink;
}
