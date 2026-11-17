import '../vision/detected_object.dart';
import '../vision/object_colour.dart';

/// Human-readable names for the detector's classes.
///
/// The model emits English names such as "mobile phone" or "pencil case".
/// Cue speaks them in the language the user chose, so each class has a Hindi
/// rendering. Names that are already loanwords or international product names
/// are transliterated rather than translated.
const Map<String, String> englishToHindiObjectLabels = {
  'person': 'व्यक्ति',
  'bicycle': 'साइकिल',
  'car': 'कार',
  'motorcycle': 'मोटरसाइकिल',
  'airplane': 'हवाई जहाज़',
  'bus': 'बस',
  'train': 'ट्रेन',
  'truck': 'ट्रक',
  'boat': 'नाव',
  'traffic light': 'ट्रैफ़िक सिग्नल',
  'fire hydrant': 'फायर हाइड्रेंट',
  'stop sign': 'स्टॉप साइन',
  'parking meter': 'पार्किंग मीटर',
  'bench': 'बेंच',
  'bird': 'पक्षी',
  'cat': 'बिल्ली',
  'dog': 'कुत्ता',
  'horse': 'घोड़ा',
  'sheep': 'भेड़',
  'cow': 'गाय',
  'elephant': 'हाथी',
  'bear': 'भालू',
  'zebra': 'ज़ेबरा',
  'giraffe': 'जिराफ़',
  'backpack': 'बैगपैक',
  'umbrella': 'छाता',
  'handbag': 'हैंडबैग',
  'tie': 'टाई',
  'suitcase': 'सूटकेस',
  'keyboard': 'कीबोर्ड',
  'computer mouse': 'कंप्यूटर माउस',
  'monitor': 'मॉनिटर',
  'mobile phone': 'फ़ोन',
  'laptop': 'लैपटॉप',
  'earphones': 'ईयरफ़ोन',
  'headphones': 'हेडफ़ोन',
  'charger': 'चार्जर',
  'pencil case': 'पेंसिल केस',
  'pen': 'पेन',
  'pencil': 'पेंसिल',
  'eraser': 'रबर',
  'marker': 'मार्कर',
  'ruler': 'स्केल',
  'notebook': 'नोटबुक',
  'book': 'किताब',
  'paper': 'काग़ज़',
  'wallet': 'बटुआ',
  'glasses': 'चश्मा',
  'keys': 'चाबियाँ',
  'flashlight': 'टॉर्च',
  'shirt': 'कमीज़',
  't-shirt': 'टी-शर्ट',
  'pants': 'पतलून',
  'shoe': 'जूता',
  'sock': 'मोज़ा',
  'cap': 'टोपी',
  'jacket': 'जैकेट',
  'cup': 'कप',
  'mug': 'मग',
  'glass': 'गिलास',
  'bottle': 'बोतल',
  'water bottle': 'पानी की बोतल',
  'thermos': 'थर्मस',
  'bowl': 'कटोरा',
  'plate': 'प्लेट',
  'spoon': 'चम्मच',
  'fork': 'काँटा',
  'knife': 'चाकू',
  'chopping board': 'चॉपिंग बोर्ड',
  'pot': 'हांडी',
  'pan': 'तवा',
  'kettle': 'केतली',
  'microwave oven': 'माइक्रोवेव',
  'washing machine': 'वाशिंग मशीन',
  'table': 'मेज़',
  'desk': 'डेस्क',
  'sofa': 'सोफ़ा',
  'pillow': 'तकिया',
  'wardrobe': 'अलमारी',
  'bookshelf': 'बुकशेल्फ़',
  'door': 'दरवाज़ा',
  'window': 'खिड़की',
  'light switch': 'लाइट का स्विच',
  'power socket': 'पावर सॉकेट',
  'fan': 'पंखा',
  'lamp': 'लैंप',
  'television': 'टीवी',
  'remote control': 'रिमोट',
  'toothbrush': 'टूथब्रश',
  'hairbrush': 'हेयरब्रश',
  'comb': 'कंघी',
  'towel': 'तौलिया',
  'soap': 'साबुन',
  'first aid kit': 'फर्स्ट एड किट',
  'fire extinguisher': 'अग्निशामक',
  'box': 'बक्सा',
  'frisbee': 'फ्रिस्बी',
  'skis': 'स्की',
  'snowboard': 'स्नोबोर्ड',
  'sports ball': 'खेल की गेंद',
  'kite': 'पतंग',
  'baseball bat': 'बैट',
  'baseball glove': 'ग्लव',
  'skateboard': 'स्केटबोर्ड',
  'surfboard': 'सर्फ़बोर्ड',
  'tennis racket': 'टेनिस रैकेट',
  'wine glass': 'गिलास',
  'banana': 'केला',
  'apple': 'सेब',
  'sandwich': 'सैंडविच',
  'orange': 'संतरा',
  'broccoli': 'ब्रोकली',
  'carrot': 'गाजर',
  'hot dog': 'हॉटडॉग',
  'pizza': 'पिज़्ज़ा',
  'donut': 'डोनट',
  'cake': 'केक',
  'chair': 'कुर्सी',
  'couch': 'सोफ़ा',
  'potted plant': 'गमले वाला पौधा',
  'bed': 'बिस्तर',
  'dining table': 'खाने की मेज़',
  'toilet': 'शौचालय',
  'tv': 'टीवी',
  'tv monitor': 'टीवी',
  'mouse': 'माउस',
  'remote': 'रिमोट',
  'cell phone': 'फ़ोन',
  'microwave': 'माइक्रोवेव',
  'oven': 'ओवन',
  'toaster': 'टोस्टर',
  'sink': 'सिंक',
  'refrigerator': 'रेफ्रिजरेटर',
  'clock': 'घड़ी',
  'vase': 'फूलदान',
  'scissors': 'कैंची',
  'teddy bear': 'टेडी बियर',
  'hair drier': 'हेयर ड्रायर',
};

/// Joins object labels into a spoken list.
///
/// English: "chair, person and bottle"
/// Hindi: "कुर्सी, व्यक्ति और बोतल"
String joinLabels(List<String> labels, {required bool hindi}) {
  if (labels.isEmpty) return '';
  if (labels.length == 1) return labels.first;
  final conjunction = hindi ? ' और' : ' and';
  if (labels.length == 2) return '${labels[0]}$conjunction ${labels[1]}';
  final leading = labels.sublist(0, labels.length - 1).join(', ');
  return '$leading$conjunction ${labels.last}';
}

/// A short, spoken sentence naming the objects seen.
///
/// English: "I see a person, a chair and a bottle."
/// Hindi:  "मुझे एक व्यक्ति, एक कुर्सी और एक बोतल दिख रही है।"
String objectAnnouncement(List<String> labels, {required bool hindi}) {
  final names = labels
      .map(
        (label) => hindi ? englishToHindiObjectLabels[label] ?? label : label,
      )
      .toList();

  if (hindi) {
    return 'मुझे ${joinLabels(names, hindi: true)} दिख रही है।';
  }

  final singular = labels.length == 1;
  final phrase = singular
      ? 'a ${names.first}'
      : joinLabels(names.map((name) => 'a $name').toList(), hindi: false);
  return 'I see $phrase.';
}

/// A spoken description of what Cue sees, where it is and roughly how far.
///
/// English: "Chair, about 2 metres away, to your left. Bottle, very close."
/// Hindi:  "कुर्सी, आपके बाईं ओर, लगभग 2 मीटर दूर। बोतल, बहुत पास।"
///
/// Distance is only spoken when the class has a meaningful real-world height;
/// guessing from the size of a pizza box would be worse than saying nothing.
String objectDescription(
  List<DetectedObject> objects, {
  required bool hindi,
  bool includeDistance = true,
}) {
  if (objects.isEmpty) return '';

  final items = objects
      .map(
        (object) => hindi
            ? _hindiObject(object, includeDistance)
            : _englishObject(object, includeDistance),
      )
      .toList();

  return items.join(hindi ? ' ' : ' ');
}

String _englishObject(DetectedObject object, bool includeDistance) {
  final colour = object.colour;
  final name = colour == null
      ? _capitalise(object.name)
      : '${_capitalise(englishColourName(colour))} ${object.name}';
  final distance = includeDistance
      ? englishDistancePhrase(object.distanceMeters)
      : null;

  switch (object.direction) {
    case ObjectDirection.ahead:
      return distance == null
          ? '$name, in front of you.'
          : '$name, $distance in front of you.';
    case ObjectDirection.left:
      return distance == null
          ? '$name, to your left.'
          : '$name, $distance, to your left.';
    case ObjectDirection.right:
      return distance == null
          ? '$name, to your right.'
          : '$name, $distance, to your right.';
  }
}

String _hindiObject(DetectedObject object, bool includeDistance) {
  final base = englishToHindiObjectLabels[object.name] ?? object.name;
  final colour = object.colour;
  final name = colour == null ? base : '${hindiColourName(colour)} $base';
  final direction = switch (object.direction) {
    ObjectDirection.ahead => 'सामने',
    ObjectDirection.left => 'आपके बाईं ओर',
    ObjectDirection.right => 'आपके दाईं ओर',
  };
  final distance = includeDistance
      ? hindiDistancePhrase(object.distanceMeters)
      : null;

  if (distance == null) return '$name, $direction।';
  return '$name, $direction, $distance।';
}

/// The answer to "what colour is this?".
///
/// The colour is sampled from the middle of the view, so the sentence says so.
/// "Mostly blue" is honest about a scene with several colours in it; "blue"
/// alone would pretend the whole picture was one object.
String colourInViewAnswer(ColourReading? reading, {required bool hindi}) {
  if (reading == null) {
    return hindi
        ? 'अभी रंग नहीं बता सकता। किसी चीज़ पर कैमरा रखें और स्थिर रखें।'
        : 'I cannot tell the colour right now. Point at something and hold '
              'steady.';
  }

  final name = hindi ? hindiColourName(reading) : englishColourName(reading);
  return hindi
      ? 'सामने का मुख्य रंग $name है।'
      : 'The middle of your view is mostly $name.';
}

/// "Looking to your left." Said before a scan that may take a second or two.
String sideLooking(ObjectDirection side, {required bool hindi}) {
  if (hindi) {
    return switch (side) {
      ObjectDirection.left => 'आपके बाईं ओर देख रहा हूँ।',
      ObjectDirection.right => 'आपके दाईं ओर देख रहा हूँ।',
      ObjectDirection.ahead => 'सामने देख रहा हूँ।',
    };
  }
  return switch (side) {
    ObjectDirection.left => 'Looking to your left.',
    ObjectDirection.right => 'Looking to your right.',
    ObjectDirection.ahead => 'Looking ahead.',
  };
}

/// The honest answer when nothing recognisable is on that side.
String nothingOnSide(ObjectDirection side, {required bool hindi}) {
  if (hindi) {
    return switch (side) {
      ObjectDirection.left => 'मुझे आपके बाईं ओर कोई चीज़ साफ़ नहीं दिख रही।',
      ObjectDirection.right => 'मुझे आपके दाईं ओर कोई चीज़ साफ़ नहीं दिख रही।',
      ObjectDirection.ahead => 'मुझे सामने कोई चीज़ साफ़ नहीं दिख रही।',
    };
  }
  return switch (side) {
    ObjectDirection.left => 'I cannot see anything clearly on your left.',
    ObjectDirection.right => 'I cannot see anything clearly on your right.',
    ObjectDirection.ahead => 'I cannot see anything clearly ahead.',
  };
}

/// Coarse spoken distance for English.
///
/// Rounded halves, because a pinhole estimate taken from a bounding box is
/// not accurate to the metre and should not sound as if it is.
String? englishDistancePhrase(double? metres) {
  if (metres == null) return null;
  if (metres < 0.6) return 'very close';
  if (metres < 1.2) return 'about a metre away';

  final halves = (metres * 2).round();
  if (halves.isOdd) {
    final whole = halves ~/ 2;
    return 'about $whole and a half metres away';
  }
  return 'about ${halves ~/ 2} metres away';
}

/// Coarse spoken distance for Hindi.
String? hindiDistancePhrase(double? metres) {
  if (metres == null) return null;
  if (metres < 0.6) return 'बहुत पास';
  if (metres < 1.2) return 'लगभग एक मीटर दूर';

  final halves = (metres * 2).round();
  if (halves.isOdd) {
    final whole = halves ~/ 2;
    return 'लगभग $whole.5 मीटर दूर';
  }
  return 'लगभग ${halves ~/ 2} मीटर दूर';
}

String _capitalise(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// A spoken message for a frame with no confident detections.
String noObjectsMessage({required bool hindi}) => hindi
    ? 'सामने कोई वस्तु स्पष्ट नहीं दिख रही। कैमरा किसी चीज़ की ओर रखें।'
    : 'I cannot see any object clearly in front of you. Point the camera at one.';
