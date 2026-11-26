import 'personal_items.dart';
import 'search_target.dart';

enum FinderAction { find, teach }

class FinderRequest {
  const FinderRequest(this.action, this.name) : commonTarget = null;
  FinderRequest.common(SearchTarget target)
    : action = FinderAction.find,
      name = target.english,
      commonTarget = target;

  final FinderAction action;
  final String name;
  final SearchTarget? commonTarget;

  static final _english = RegExp(
    r'^(?:(?:can|could|would) you )?(?:please )?(find|look for|search for|teach(?: cue)?|learn) (?:(?:my|the|a|an) )?(.+)$',
  );
  static final _hindi = RegExp(
    r'^(?:(?:मेरी|मेरा|मेरे|एक) )?(.+?) (खोजो|खोजें|ढूंढो|ढूँढो|ढूँढें|सीखो|सीखें)$',
  );

  static FinderRequest? parse(String words) {
    final text = normalizeItemName(words).replaceFirst(RegExp(r' please$'), '');
    if (text == 'find' || text == 'find an item' || text == 'चीज़ खोजें') {
      return const FinderRequest(FinderAction.find, '');
    }
    if (text == 'teach' || text == 'teach an item' || text == 'नई चीज़ सीखो') {
      return const FinderRequest(FinderAction.teach, '');
    }
    final english = _english.firstMatch(text);
    if (english != null) {
      final verb = english[1]!;
      return FinderRequest(
        verb.startsWith('teach') || verb == 'learn'
            ? FinderAction.teach
            : FinderAction.find,
        english[2]!,
      );
    }
    final hindi = _hindi.firstMatch(text);
    if (hindi != null) {
      return FinderRequest(
        hindi[2]!.startsWith('सीख') ? FinderAction.teach : FinderAction.find,
        hindi[1]!,
      );
    }
    return null;
  }
}

SearchTarget? builtInFinderTarget(String name) {
  final query = personalItemKey(name);
  for (final target in SearchTarget.values) {
    if (query == normalizeItemName(target.english) ||
        query == normalizeItemName(target.hindi) ||
        target.labels.contains(query) ||
        target.aliases.contains(query)) {
      return target;
    }
  }
  return switch (query) {
    'key' ||
    'car key' ||
    'house key' ||
    'door key' ||
    'ignition key' ||
    'key ring' ||
    'keyring' => SearchTarget.keys,
    'mobile' || 'मोबाइल' => SearchTarget.phone,
    'eyeglasses' || 'spectacles' => SearchTarget.glasses,
    'कलम' => SearchTarget.pen,
    _ => null,
  };
}

PersonalItem? taughtFinderItem(Iterable<PersonalItem> items, String name) {
  final key = personalItemKey(name);
  for (final item in items) {
    if (item.key == key) return item;
  }
  if (!_penDriveNames.contains(key)) return null;

  // Voice recognition can use a different name for the same USB drive.
  // Keep exact saved names usable when more than one drive has been taught.
  final matches = items
      .where((item) => _penDriveNames.contains(item.key))
      .take(2)
      .toList();
  return matches.length == 1 ? matches.single : null;
}

const _penDriveNames = {
  'pen drive',
  'pendrive',
  'usb drive',
  'usb flash drive',
  'usb stick',
  'flash drive',
  'thumb drive',
  'पेन ड्राइव',
};
