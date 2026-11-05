/// Human-readable names for the 80 classes YOLO was trained on.
///
/// The model emits English names such as "cell phone" or "dining table".
/// Cue speaks them in the language the user chose, so each class has a
/// Hindi rendering. Names that are already loanwords or international
/// product names are transliterated rather than translated.
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
  'bottle': 'बोतल',
  'wine glass': 'गिलास',
  'cup': 'कप',
  'fork': 'काँटा',
  'knife': 'चाकू',
  'spoon': 'चम्मच',
  'bowl': 'कटोरा',
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
  'laptop': 'लैपटॉप',
  'mouse': 'माउस',
  'remote': 'रिमोट',
  'keyboard': 'कीबोर्ड',
  'cell phone': 'फ़ोन',
  'microwave': 'माइक्रोवेव',
  'oven': 'ओवन',
  'toaster': 'टोस्टर',
  'sink': 'सिंक',
  'refrigerator': 'रेफ्रिजरेटर',
  'book': 'किताब',
  'clock': 'घड़ी',
  'vase': 'फूलदान',
  'scissors': 'कैंची',
  'teddy bear': 'टेडी बियर',
  'hair drier': 'हेयर ड्रायर',
  'toothbrush': 'टूथब्रश',
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

/// A spoken message for a frame with no confident detections.
String noObjectsMessage({required bool hindi}) => hindi
    ? 'सामने कोई वस्तु स्पष्ट नहीं दिख रही। कैमरा किसी चीज़ की ओर रखें।'
    : 'I cannot see any object clearly in front of you. Point the camera at one.';
