import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

String normalizeItemName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

String personalItemKey(String name) =>
    normalizeItemName(name)
        .replaceFirst(RegExp(r'^(?:my|the|an?|मेरी|मेरा|मेरे|एक) '), '');

class PersonalExample {
  PersonalExample({
    required this.format,
    required List<double> foreground,
    required Iterable<List<double>> background,
  }) : foreground = unitEmbedding(foreground),
       background = List.unmodifiable(background.map(unitEmbedding)) {
    if (format.isEmpty ||
        this.background.isEmpty ||
        this.background.any(
          (vector) => vector.length != this.foreground.length,
        )) {
      throw const FormatException('Incompatible visual examples');
    }
  }

  factory PersonalExample.fromJson(Map<String, dynamic> json) =>
      PersonalExample(
        format: json['format'] as String,
        foreground: _numbers(json['item']),
        background: (json['background'] as List).map(_numbers),
      );

  final String format;
  final List<double> foreground;
  final List<List<double>> background;

  Map<String, Object> toJson() => {
    'format': format,
    'item': foreground,
    'background': background,
  };

  static List<double> _numbers(Object? input) =>
      (input as List).cast<num>().map((value) => value.toDouble()).toList();
}

List<double> unitEmbedding(List<double> values) {
  var squaredLength = 0.0;
  for (final value in values) {
    squaredLength += value * value;
  }
  if (squaredLength <= 0 || !squaredLength.isFinite) {
    throw const FormatException('Invalid visual embedding');
  }
  final length = math.sqrt(squaredLength);
  return List.unmodifiable(values.map((value) => value / length));
}

double embeddingSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return -1;
  var similarity = 0.0;
  for (var i = 0; i < a.length; i++) {
    similarity += a[i] * b[i];
  }
  return similarity.clamp(-1.0, 1.0);
}

class PersonalItem {
  PersonalItem(String name, Iterable<PersonalExample> examples)
    : name = name.trim(),
      examples = List.unmodifiable(examples) {
    if (key.isEmpty ||
        this.examples.length < examplesToTeach ||
        this.examples.any(
          (example) =>
              example.format != format ||
              example.foreground.length !=
                  this.examples.first.foreground.length,
        )) {
      throw const FormatException('Invalid personal item');
    }
  }

  factory PersonalItem.fromJson(Map<String, dynamic> json) => PersonalItem(
    json['name'] as String,
    (json['examples'] as List).map(
      (entry) =>
          PersonalExample.fromJson(Map<String, dynamic>.from(entry as Map)),
    ),
  );

  static const int examplesToTeach = 3;

  final String name;
  final List<PersonalExample> examples;
  String get key => personalItemKey(name);
  String get format => examples.first.format;

  /// Compare a window with both the saved views and their backgrounds.
  /// Return null unless the item is a substantially better match.
  double? score(List<double> embedding) {
    var foreground = -1.0;
    var background = -1.0;
    for (final example in examples) {
      foreground = math.max(
        foreground,
        embeddingSimilarity(embedding, example.foreground),
      );
      for (final negative in example.background) {
        background = math.max(
          background,
          embeddingSimilarity(embedding, negative),
        );
      }
    }
    if (foreground < 0.65 || foreground - background < 0.13) return null;
    return foreground;
  }

  Map<String, Object> toJson() => {'name': name, 'examples': examples};
}

/// Application-private visual profiles, written atomically after teaching.
class PersonalItemStore {
  PersonalItemStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _privateDirectory;

  static final instance = PersonalItemStore();

  final Future<Directory> Function() _directory;
  Future<void> _writes = Future.value();

  static Future<Directory> _privateDirectory() async {
    final path = await const MethodChannel('cue/personal_items')
        .invokeMethod<String>('profileDirectory');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('No personal item storage directory');
    }
    return Directory(path);
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}/cue_personal_items.json');

  Future<List<PersonalItem>> read() async {
    await _writes;
    return _read(await _file());
  }

  Future<List<PersonalItem>> _read(File file) async {
    if (!await file.exists()) return const [];
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Unknown personal item format');
    }
    return (data['items'] as List)
        .map(
          (entry) =>
              PersonalItem.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList();
  }

  Future<void> save(PersonalItem item) => _change((items) {
    items.removeWhere((other) => other.key == item.key);
    items.add(item);
    items.sort((a, b) => a.key.compareTo(b.key));
  });

  Future<void> forget(PersonalItem item) =>
      _change((items) => items.removeWhere((other) => other.key == item.key));

  Future<void> _change(void Function(List<PersonalItem>) update) {
    final operation = _writes.then((_) async {
      final file = await _file();
      final items = [...await _read(file)];
      update(items);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.new');
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'items': items}),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _writes = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}
