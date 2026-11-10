import 'dart:ui';

import 'object_colour.dart';

/// Where an object sits relative to the person holding the phone.
///
/// "Left" and "right" are the user's own left and right, which is the same as
/// the camera's when the phone is held out in front.
enum ObjectDirection { left, ahead, right }

/// One object the detector found, with the geometry Cue needs to describe it.
///
/// The raw plugin result only carries a name, a score and a box. A blind user
/// needs to know *where* the thing is and roughly *how far*, so the box is
/// kept and turned into a direction and a coarse distance.
class DetectedObject {
  const DetectedObject({
    required this.name,
    required this.confidence,
    required this.box,
    this.colour,
  });

  /// Model class name, lower case, exactly as the model emits it.
  final String name;

  /// Model confidence, 0.0 - 1.0.
  final double confidence;

  /// Normalised box: 0 - 1 across the camera frame, origin at top-left.
  final Rect box;

  /// The colour Cue sampled from the middle of the box, when it is known.
  ///
  /// Null is honest: a box that is too small, or a frame that could not be
  /// decoded, produces no colour rather than a guess.
  final ColourReading? colour;

  /// This object with a sampled colour attached.
  DetectedObject withColour(ColourReading? reading) => DetectedObject(
    name: name,
    confidence: confidence,
    box: box,
    colour: reading,
  );

  /// Which way the user should turn to face the object.
  ObjectDirection get direction {
    final centre = box.center.dx;
    if (centre < 0.36) return ObjectDirection.left;
    if (centre > 0.64) return ObjectDirection.right;
    return ObjectDirection.ahead;
  }

  /// How much of the frame the object fills. Used for ranking and distance.
  double get area => box.width * box.height;

  /// Rough distance in metres, or null when no honest estimate is possible.
  ///
  /// This is the pinhole-camera identity: a known real-world height divided by
  /// the fraction of the frame the object fills. The constant converts frame
  /// height into focal length for a typical phone camera.
  ///
  /// It is deliberately coarse. A bottle seen end-on, a person sitting down,
  /// or a cropped object all break the assumption, so Cue only ever speaks
  /// rounded bands from this number.
  double? get distanceMeters {
    final realHeight = realHeights[name];
    if (realHeight == null) return null;

    final fraction = box.height;
    if (fraction < 0.02 || fraction > 1.0) return null;

    final metres = realHeight * _focalOverFrameHeight / fraction;
    if (!metres.isFinite || metres <= 0) return null;
    return metres.clamp(0.3, 15.0);
  }

  /// Whether this class stands upright in the real world.
  bool get isTallClass => _tallClasses.contains(name);

  /// Whether the box has the proportions an upright object would have.
  /// A "bottle" that is wider than it is tall is almost always a table edge.
  bool get hasTallShape => box.height >= box.width * 0.7;

  @override
  String toString() =>
      '$name ${(confidence * 100).round()}% '
      '${direction.name} ${distanceMeters?.toStringAsFixed(1) ?? '?'}m'
      '${colour == null ? '' : ' ${englishColourName(colour!)}'}';
}

/// Focal length divided by frame height for a phone rear camera, roughly a
/// 50 degree vertical field of view. Kept as one constant so the estimate can
/// be tuned in one place.
const double _focalOverFrameHeight = 1.05;

/// Classes that are plausible household/everyday objects but are often
/// mistaken by an object detector. An ordinary shoe or pencil case is allowed
/// to be spoken confidently, but a refrigerator, wallet or phone needs more
/// evidence before Cue risks a wrong name.
const Set<String> strictObjectClasses = {
  'refrigerator',
  'washing machine',
  'microwave oven',
  'fire extinguisher',
  'first aid kit',
  'suitcase',
  'handbag',
  'backpack',
  'mobile phone',
  'keys',
  'wallet',
  'glasses',
  'cup',
  'mug',
  'glass',
  'pot',
  'pan',
  'plate',
  'bowl',
  'book',
  'box',
};

/// Confidence a strict class must reach before it is spoken.
const double strictClassConfidence = 0.75;

/// Floor below which an ordinary class is almost always a misread.
const double ordinaryClassConfidence = 0.60;

/// Confidence a manual request requires for a strict class.
const double strictManualClassConfidence = 0.68;

/// Approximate real-world heights in metres for classes where height is a
/// stable, meaningful measure. Flat things (pizza, keyboard, skateboard) and
/// long diagonal things (skis, surfboard) are deliberately absent: their box
/// height says almost nothing about distance.
const Map<String, double> realHeights = {
  'person': 1.70,
  'bicycle': 1.00,
  'car': 1.50,
  'motorcycle': 1.10,
  'bus': 3.00,
  'train': 3.40,
  'truck': 3.00,
  'boat': 1.00,
  'traffic light': 1.00,
  'fire hydrant': 0.90,
  'stop sign': 0.75,
  'parking meter': 1.20,
  'bench': 0.85,
  'chair': 0.90,
  'couch': 0.80,
  'potted plant': 0.50,
  'bed': 0.55,
  'dining table': 0.75,
  'toilet': 0.75,
  'tv': 0.55,
  'laptop': 0.25,
  'book': 0.24,
  'bottle': 0.25,
  'wine glass': 0.18,
  'cup': 0.10,
  'bowl': 0.09,
  'fork': 0.18,
  'knife': 0.25,
  'spoon': 0.18,
  'banana': 0.18,
  'apple': 0.08,
  'orange': 0.08,
  'carrot': 0.18,
  'broccoli': 0.15,
  'suitcase': 0.65,
  'backpack': 0.45,
  'handbag': 0.30,
  'umbrella': 0.90,
  'tie': 0.40,
  'refrigerator': 1.80,
  'microwave': 0.35,
  'microwave oven': 0.35,
  'oven': 0.70,
  'washing machine': 0.85,
  'monitor': 0.45,
  'television': 0.55,
  'table': 0.75,
  'desk': 0.75,
  'sofa': 0.80,
  'pillow': 0.18,
  'wardrobe': 1.80,
  'bookshelf': 1.80,
  'door': 2.00,
  'window': 1.00,
  'lamp': 0.50,
  'thermos': 0.30,
  'water bottle': 0.25,
  'mug': 0.12,
  'kettle': 0.28,
  'pot': 0.18,
  'pan': 0.10,
  'fire extinguisher': 0.50,
  'box': 0.35,
  'wallet': 0.09,
  'cap': 0.18,
  'shoe': 0.15,
  'toaster': 0.25,
  'sink': 0.30,
  'clock': 0.30,
  'vase': 0.30,
  'scissors': 0.20,
  'teddy bear': 0.40,
  'hair drier': 0.20,
  'toothbrush': 0.18,
  'cell phone': 0.15,
  'mobile phone': 0.15,
  'remote': 0.15,
  'remote control': 0.15,
  'mouse': 0.08,
  'sports ball': 0.22,
};

/// Classes the detector reaches for when it does not know what it is looking
/// at: food, sports gear and tiny utensils. On a desk, a pen becomes a
/// "carrot" and a stapler becomes a "hot dog". These are only spoken when the
/// model is unusually sure, because for a blind user a confident wrong name is
/// worse than silence.
const Set<String> riskyObjectClasses = {
  'banana',
  'apple',
  'orange',
  'broccoli',
  'carrot',
  'hot dog',
  'pizza',
  'donut',
  'cake',
  'sandwich',
  'frisbee',
  'sports ball',
  'kite',
  'baseball bat',
  'baseball glove',
  'skateboard',
  'surfboard',
  'skis',
  'snowboard',
  'tennis racket',
  'fork',
  'knife',
  'spoon',
  'scissors',
  'toothbrush',
  'hair drier',
  'teddy bear',
};

/// Confidence a risky class must reach before it is spoken.
const double riskyClassConfidence = 0.78;

/// Whether a detection is strong enough to be spoken on its own.
///
/// [lenient] is for a manual double-tap: the user asked, so the bar for
/// ordinary objects drops a little. Risky classes keep the higher bar either
/// way, because "carrot" for a pen is not an answer worth giving.
/// Minimum frame area expected for large classes.
///
/// A refrigerator, a wardrobe or a sofa that fills 1% of the frame is not a
/// meaningful close-range answer; it is almost certainly a book, a wall edge
/// or a table leg. The threshold is deliberately small so the filter catches
/// obvious misreads without muting far-away furniture.
const Map<String, double> minAreaForLargeClasses = {
  'refrigerator': 0.06,
  'washing machine': 0.06,
  'wardrobe': 0.06,
  'bookshelf': 0.06,
  'sofa': 0.05,
  'bed': 0.05,
  'chair': 0.02,
  'dining table': 0.025,
  'table': 0.025,
  'desk': 0.025,
  'door': 0.03,
  'window': 0.02,
  'microwave oven': 0.02,
};

/// Whether [object] is plausibly the size the class usually has.
bool hasPlausibleLargeClassArea(DetectedObject object) {
  final minimum = minAreaForLargeClasses[object.name];
  return minimum == null || object.area >= minimum;
}

bool isConfidentDetection(DetectedObject object, {required bool lenient}) {
  if (riskyObjectClasses.contains(object.name)) {
    return object.confidence >= riskyClassConfidence;
  }
  if (strictObjectClasses.contains(object.name)) {
    if (lenient && object.confidence >= strictManualClassConfidence) {
      return true;
    }
    return object.confidence >= strictClassConfidence;
  }
  return object.confidence >= (lenient ? 0.50 : ordinaryClassConfidence);
}

/// Classes that are tall in the real world, so a wide, flat box is suspicious.
const Set<String> _tallClasses = {
  'person',
  'bottle',
  'wine glass',
  'cup',
  'fork',
  'knife',
  'spoon',
  'toothbrush',
  'traffic light',
  'stop sign',
  'parking meter',
  'fire hydrant',
  'potted plant',
  'vase',
  'umbrella',
  'refrigerator',
  'microwave oven',
  'door',
  'wardrobe',
  'bookshelf',
  'fire extinguisher',
  'thermos',
  'hair drier',
};
