import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:archive/archive.dart';
import 'package:cue/core/object_labels.dart';
import 'package:cue/vision/object_detect_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the Android detector bundles each household label in export order',
    () async {
      final original = await _modelLabels(
        ObjectDetectService.everydayModelPath,
      );
      final expanded = await _modelLabels(ObjectDetectService.modelPath);
      final manifest = await File('tool/object_model/household_labels.tsv')
          .readAsLines();
      final entries = manifest
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .map((line) => line.split('\t'))
          .toList();

      expect(original, hasLength(76));
      expect(original, containsAll(['person', 'keys']));
      expect(entries, hasLength(218));
      expect(expanded, [...original, ...entries.map((entry) => entry[0])]);
      expect(expanded.toSet(), hasLength(294));
      for (final entry in entries) {
        expect(englishToHindiObjectLabels[entry[0]], entry[1]);
      }
    },
  );
}

Future<List<String>> _modelLabels(String path) async {
  final data = await rootBundle.load(path);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  // The export appends a ZIP with the labels used by the native detector.
  final metadata = ZipDecoder().decodeBytes(bytes).find('metadata.json');
  expect(metadata, isNotNull);
  final json = jsonDecode(utf8.decode(metadata!.content)) as Map;
  final names = json['names'] as Map;
  return List.generate(names.length, (index) => names['$index'] as String);
}
