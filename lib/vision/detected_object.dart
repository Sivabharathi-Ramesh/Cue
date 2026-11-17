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
    this.spokenAs,
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

  /// A safer label to speak when the model is not sure enough to name the
  /// class, for example "small object" when a comb and a knife score almost
  /// the same. Null means the model class is trustworthy enough to say.
  ///
  /// The raw [name] is kept for thresholds, logging and the developer overlay.
  final String? spokenAs;

  /// The label Cue should actually speak.
  String get label => spokenAs ?? name;

  /// Whether the model offered competing names for this box.
  bool get isAmbiguous => spokenAs != null;

  /// This object with a sampled colour attached.
  DetectedObject withColour(ColourReading? reading) => DetectedObject(
    name: name,
    confidence: confidence,
    box: box,
    colour: reading,
    spokenAs: spokenAs,
  );

  /// This object with a safer, non-committal label.
  DetectedObject withSpokenAs(String label) => DetectedObject(
    name: name,
    confidence: confidence,
    box: box,
    colour: colour,
    spokenAs: label,
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
  /// It is deliberately narrow. Only classes with a stable upright height get
  /// an estimate at all. A comb, marker, pen or knife lying on a desk has a
  /// box height equal to its thickness, not its length, so the same formula
  /// would report it metres away when it is in the user's hand. Flat things,
  /// folded clothes and objects with wildly varying sizes are absent from
  /// [realHeights] for that reason.
  ///
  /// A box cut off by the top or bottom of the frame is also refused: the
  /// missing part makes the object look smaller, which reads as farther away.
  double? get distanceMeters {
    if (isAmbiguous) return null;
    if (isVerticallyCropped) return null;

    final realHeight = realHeights[name];
    if (realHeight == null) return null;

    // A "bottle" that is wider than it is tall is lying down, or is a table
    // edge. Its vertical extent is not its height.
    if (isTallClass && !hasTallShape) return null;

    final fraction = box.height;
    if (fraction < 0.02 || fraction > 1.0) return null;

    final metres = realHeight * _focalOverFrameHeight / fraction;
    if (!metres.isFinite || metres <= 0) return null;

    final limit = realHeight < _smallObjectHeight
        ? _maxSmallObjectDistance
        : _maxObjectDistance;
    if (metres > limit) return null;
    return metres.clamp(0.3, limit);
  }

  /// Whether the top or bottom of the box is cut off by the frame.
  ///
  /// Only vertical cropping matters for distance, because the estimate uses
  /// the box's height. A box touching the left or right edge keeps its full
  /// height and remains usable.
  bool get isVerticallyCropped => box.top <= 0.02 || box.bottom >= 0.98;

  /// Whether this class stands upright in the real world.
  bool get isTallClass => _tallClasses.contains(name);

  /// Whether the box has the proportions an upright object would have.
  /// A "bottle" that is wider than it is tall is almost always a table edge.
  bool get hasTallShape => box.height >= box.width * 0.7;

  @override
  String toString() {
    final spoken = isAmbiguous ? '$name as $label' : name;
    return '$spoken ${(confidence * 100).round()}% '
        '${direction.name} ${distanceMeters?.toStringAsFixed(1) ?? '?'}m'
        '${colour == null ? '' : ' ${englishColourName(colour!)}'}';
  }
}

/// Focal length divided by frame height for a phone rear camera, roughly a
/// 50 degree vertical field of view. Kept as one constant so the estimate can
/// be tuned in one place.
const double _focalOverFrameHeight = 1.05;

/// Anything shorter than this (in metres) is treated as a small, close-range
/// object. Beyond [_maxSmallObjectDistance] its box is too small to trust.
const double _smallObjectHeight = 0.40;
const double _maxSmallObjectDistance = 6.0;
const double _maxObjectDistance = 15.0;

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
  // Small desk and bathroom things. These are the classes the detector
  // reaches for when it sees texture rather than an object, so they need more
  // evidence before a blind user is told what they are holding.
  'pen',
  'pencil',
  'eraser',
  'marker',
  'ruler',
  'charger',
  'earphones',
  'headphones',
  'pencil case',
  'notebook',
  'paper',
  'light switch',
  'power socket',
  'remote control',
  'toothbrush',
  'hairbrush',
  'comb',
  'soap',
  'towel',
};

/// Confidence a strict class must reach before it is spoken.
const double strictClassConfidence = 0.75;

/// Floor below which an ordinary class is almost always a misread.
const double ordinaryClassConfidence = 0.60;

/// Confidence a manual request requires for a strict class.
const double strictManualClassConfidence = 0.68;

/// Approximate real-world heights in metres for classes where height is a
/// stable, meaningful measure.
///
/// This map is deliberately short. It is the *only* gate for a numeric
/// distance, so anything whose box height is not its real height is left out:
/// flat things (paper, notebook, keyboard, pizza), long diagonal things
/// (marker, pen, knife, fork, comb, ruler), folded clothes, and classes whose
/// label covers very different sizes (fan, television, lamp, box).
///
/// Upright containers are included, but [DetectedObject.distanceMeters] also
/// checks the box shape, so a bottle lying on its side gets no estimate.
const Map<String, double> realHeights = {
  'person': 1.70,
  'chair': 0.90,
  'dining table': 0.75,
  'table': 0.75,
  'desk': 0.75,
  'sofa': 0.80,
  'door': 2.00,
  'refrigerator': 1.80,
  'washing machine': 0.85,
  'wardrobe': 1.80,
  'bookshelf': 1.80,
  'microwave oven': 0.35,
  'monitor': 0.45,
  'fire extinguisher': 0.50,
  'bottle': 0.25,
  'water bottle': 0.25,
  'thermos': 0.30,
  'cup': 0.10,
  'mug': 0.12,
  'glass': 0.14,
  'kettle': 0.28,
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

/// Classes that look alike enough that a high score on one is not proof.
///
/// A comb, a hairbrush and a toothbrush are thin and elongated; a pen, pencil
/// and marker are thin and elongated; a knife, fork and spoon are thin and
/// elongated. A small detector trained on a wishlist of labels will flip
/// between them on the same box. When two of these score close together, Cue
/// speaks the group name instead of guessing the individual class.
const Map<String, Set<String>> confusableObjectGroups = {
  'grooming item': {'comb', 'hairbrush', 'toothbrush'},
  'writing tool': {'pen', 'pencil', 'marker', 'ruler'},
  'utensil': {'knife', 'fork', 'spoon'},
};

/// How close the top two labels may be before the name is not trusted.
///
/// Int8 detector scores are not calibrated probabilities, so 0.75 does not
/// mean "75% sure". The gap between first and second place is the better
/// signal: a clear winner is usually right, a near-tie is a coin flip.
const double confusableLabelMargin = 0.18;

/// The group a class belongs to, or null when it is not in a confusable set.
String? confusableGroupFor(String name) {
  for (final entry in confusableObjectGroups.entries) {
    if (entry.value.contains(name)) return entry.key;
  }
  return null;
}

/// Whether [name] is one of the classes that needs a margin check.
bool isConfusableObject(String name) => confusableGroupFor(name) != null;

/// A safe label for a box whose candidates disagree.
///
/// If every candidate is in the same group ("comb" and "hairbrush"), the group
/// name is still useful. If they cross groups ("comb" and "knife"), the only
/// honest answer is "small object".
String ambiguousObjectLabel(Iterable<String> candidates) {
  final groups = <String>{};
  for (final name in candidates) {
    final group = confusableGroupFor(name);
    if (group == null) return 'small object';
    groups.add(group);
  }
  return groups.length == 1 ? groups.single : 'small object';
}

/// Re-labels [object] when a competing class sits on the same box with almost
/// the same score.
///
/// The raw class is kept in [DetectedObject.name], so strict/risky thresholds
/// and debug logging still see it. Only what Cue says changes.
DetectedObject resolveObjectAmbiguity(
  DetectedObject object,
  Iterable<DetectedObject> peers,
) {
  if (!isConfusableObject(object.name)) return object;

  DetectedObject? rival;
  for (final other in peers) {
    if (identical(other, object)) continue;
    if (other.name == object.name) continue;
    // Only labels drawn around the same physical thing can contradict each
    // other. A separate object elsewhere in the frame must not. The threshold
    // matches the service's duplicate-box merge, so an ambiguous pair is always
    // collapsed to one instance instead of becoming "two small objects".
    if (_boxIou(object.box, other.box) < 0.55) continue;
    if (rival == null || other.confidence > rival.confidence) rival = other;
  }

  if (rival == null) return object;
  if (object.confidence - rival.confidence >= confusableLabelMargin) {
    return object;
  }
  return object.withSpokenAs(
    ambiguousObjectLabel(<String>[object.name, rival.name]),
  );
}

double _boxIou(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.width <= 0 || intersection.height <= 0) return 0;
  final intersectionArea = intersection.width * intersection.height;
  final union = a.width * a.height + b.width * b.height - intersectionArea;
  return union <= 0 ? 0 : intersectionArea / union;
}

/// Whether a detection is strong enough to be spoken on its own.
///
/// [lenient] is for a manual double-tap: the user asked, so the bar for
/// ordinary objects drops a little. Risky classes keep the higher bar either
/// way, because "carrot" for a pen is not an answer worth giving.
///
/// An ambiguous box is different. Cue is not going to say the raw class, only
/// "small object" or "writing tool", so the ordinary bar is enough: the
/// sentence is honest even when the fine-grained name is not.
bool isConfidentDetection(DetectedObject object, {required bool lenient}) {
  if (object.isAmbiguous) {
    return object.confidence >= (lenient ? 0.50 : ordinaryClassConfidence);
  }
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
  'door',
  'wardrobe',
  'bookshelf',
  'fire extinguisher',
  'thermos',
};
