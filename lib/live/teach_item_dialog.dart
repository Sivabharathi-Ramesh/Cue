import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../core/cue_strings.dart';
import '../core/finder_request.dart';
import '../core/personal_items.dart';
import '../vision/personal_item_vision.dart';

class TeachItemDialog extends StatefulWidget {
  const TeachItemDialog({
    super.key,
    required this.strings,
    required this.camera,
    required this.items,
    required this.sayName,
    required this.capture,
    required this.save,
    required this.announce,
    this.volumeShortcut,
    this.initialName = '',
  });

  final CueStrings strings;
  final ValueListenable<CameraController?> camera;
  final List<PersonalItem> items;
  final Future<String?> Function() sayName;
  final Future<PersonalExample> Function() capture;
  final Future<void> Function(PersonalItem) save;
  final Future<void> Function(String) announce;
  final Listenable? volumeShortcut;
  final String initialName;

  @override
  State<TeachItemDialog> createState() => _TeachItemDialogState();
}

class _TeachItemDialogState extends State<TeachItemDialog> {
  static const _repositionTime = Duration(seconds: 4);

  CueStrings get _strings => widget.strings;
  late final _name = TextEditingController(text: widget.initialName);
  final _examples = <PersonalExample>[];
  String? _profileName;
  String? _stepMessage;
  String? _error;
  bool _listening = false;
  bool _working = false;
  bool _saving = false;
  bool get _busy => _listening || _working || _saving;
  bool get _readyToSave => _examples.length == PersonalItem.examplesToTeach;
  bool get _isActive => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    widget.volumeShortcut?.addListener(_primaryAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isActive) return;
      if (widget.initialName.trim().isEmpty) {
        unawaited(widget.announce(_namePrompt));
      } else {
        unawaited(_continue());
      }
    });
  }

  @override
  void dispose() {
    widget.volumeShortcut?.removeListener(_primaryAction);
    _name.dispose();
    super.dispose();
  }

  void _report(String error) {
    setState(() => _error = error);
    unawaited(widget.announce(error));
  }

  String get _namePrompt => _strings.teachNamePrompt(
    hasVolumeShortcut: widget.volumeShortcut != null,
  );

  String get _placement =>
      _strings.teachPlacement(hasVolumeShortcut: widget.volumeShortcut != null);

  void _primaryAction() {
    if (_profileName == null) {
      unawaited(_sayName());
    } else {
      unawaited(_startCapture());
    }
  }

  Future<void> _sayName() async {
    if (!_isActive || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _listening = true;
      _error = null;
    });
    final spoken = await widget.sayName();
    if (!_isActive) return;
    final request = spoken == null ? null : FinderRequest.parse(spoken);
    final name = request?.action == FinderAction.teach ? request!.name : spoken;
    setState(() {
      _listening = false;
      if (name == null) {
        _error = _strings.nameNotHeard;
      } else {
        _name.text = name;
      }
    });
    if (name != null) await _continue();
  }

  Future<void> _continue() async {
    if (!_isActive || _busy) return;
    final name = _name.text.trim();
    if (personalItemKey(name).isEmpty) {
      _report(_strings.itemNameNeeded);
      return;
    }
    if (name.characters.length > 60) {
      _report(_strings.itemNameTooLong);
      return;
    }
    FocusScope.of(context).unfocus();
    final alreadySaved = widget.items.any(
      (item) => item.key == personalItemKey(name),
    );
    if (alreadySaved) {
      setState(() => _working = true);
      final question = _strings.replaceItemQuestion(name);
      unawaited(widget.announce(question));
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_strings.confirmReplace),
            ),
          ],
        ),
      );
      if (!_isActive) return;
      setState(() => _working = false);
      if (replace != true) return;
    }
    setState(() {
      _profileName = name;
      _error = null;
    });
    unawaited(widget.announce('${_strings.teachingItem(name)}. $_placement'));
  }

  Future<void> _startCapture() async {
    if (!_isActive || _busy || _profileName == null) return;
    if (_readyToSave) {
      await _save();
      return;
    }
    var retry = _error != null;
    var automaticallyRetried = false;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      while (!_readyToSave) {
        final count = _examples.length;
        final reposition = count > 0 && !retry;
        await _guide(
          retry ? _strings.holdForPhoto : _strings.teachingPrompt(count),
        );
        if (!_isActive) return;
        if (reposition) {
          await Future<void>.delayed(_repositionTime);
          if (!_isActive) return;
          await _guide(_strings.holdForPhoto);
          if (!_isActive) return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!_isActive) return;

        setState(() => _stepMessage = _strings.capturingExample);
        PersonalExample? example;
        var captureIssue = _strings.itemCaptureDifferent;
        try {
          example = await widget.capture();
        } on UnclearPersonalExample catch (error) {
          captureIssue = error.tooDark
              ? _strings.itemCaptureDark
              : _strings.itemCaptureUnclear;
        }
        if (!_isActive) return;
        final captured = example;
        if (captured == null ||
            (_examples.isNotEmpty &&
                !_examples.any(
                  (saved) =>
                      saved.format == captured.format &&
                      embeddingSimilarity(
                            saved.foreground,
                            captured.foreground,
                          ) >=
                          0.55,
                ))) {
          if (automaticallyRetried) {
            final shortcut = _strings.teachingRetryControl(
              hasVolumeShortcut: widget.volumeShortcut != null,
            );
            _report('$captureIssue $shortcut');
            return;
          }
          automaticallyRetried = true;
          retry = true;
          await _guide('$captureIssue ${_strings.teachingAutoRetry}');
          if (!_isActive) return;
          await Future<void>.delayed(_repositionTime);
          if (!_isActive) return;
          continue;
        }
        setState(() => _examples.add(captured));
        unawaited(HapticFeedback.selectionClick());
        retry = false;
        automaticallyRetried = false;
      }
      await _save();
    } catch (_) {
      if (_isActive) _report(_strings.itemCaptureError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _guide(String message) async {
    setState(() => _stepMessage = message);
    await widget.announce(message);
  }

  void _changeName() {
    setState(() {
      _profileName = null;
      _error = null;
    });
    unawaited(widget.announce(_namePrompt));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = PersonalItem(_profileName!, _examples);
      await widget.save(item);
      if (mounted && _isActive) Navigator.pop(context, item);
    } catch (_) {
      if (_isActive) _report(_strings.itemSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profileName;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          name == null ? _strings.teachItem : _strings.teachingItem(name),
        ),
        content: name == null ? _nameStep() : _captureStep(),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(_strings.cancel),
          ),
        ],
      ),
    );
  }

  Widget _nameStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      FilledButton.icon(
        autofocus: true,
        onPressed: _busy ? null : _sayName,
        icon: const Icon(Icons.mic),
        label: Text(
          _listening ? _strings.listeningLabel : _strings.sayItemName,
        ),
      ),
      if (_error case final error?) Text(error),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(_strings.typeItemName),
        children: [
          TextField(
            controller: _name,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _continue(),
            decoration: InputDecoration(labelText: _strings.itemName),
          ),
          TextButton(
            onPressed: _busy ? null : _continue,
            child: Text(_strings.next),
          ),
        ],
      ),
    ],
  );

  Widget _captureStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        _strings.teachingProgress(
          _examples.length,
          PersonalItem.examplesToTeach,
        ),
      ),
      const SizedBox(height: 8),
      Text(switch ((_saving, _working, _error)) {
        (true, _, _) => _strings.savingItem,
        (_, _, final error?) => error,
        (_, true, _) => _stepMessage ?? _strings.capturingExample,
        _ => _placement,
      }),
      const SizedBox(height: 12),
      if (!_busy)
        FilledButton.icon(
          autofocus: true,
          onPressed: _startCapture,
          icon: Icon(_readyToSave ? Icons.check : Icons.camera_alt_outlined),
          label: Text(
            _readyToSave
                ? _strings.saveItem
                : _error == null
                ? _strings.startCapture
                : _strings.retryCapture,
          ),
        ),
      if (!_readyToSave) _preview(),
      if (!_busy && _examples.isEmpty)
        TextButton(
          onPressed: _changeName,
          child: Text(_strings.changeItemName),
        ),
    ],
  );

  Widget _preview() => ExcludeSemantics(
    child: ValueListenableBuilder<CameraController?>(
      valueListenable: widget.camera,
      builder: (context, camera, _) {
        if (camera == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 212, maxWidth: 260),
              child: CameraPreview(
                camera,
                child: const CustomPaint(painter: _TeachGuidePainter()),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TeachGuidePainter extends CustomPainter {
  const _TeachGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * PersonalItemVision.guideFraction;
    final guide = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: side,
        height: side,
      ),
      const Radius.circular(12),
    );
    final outline = Paint()..style = PaintingStyle.stroke;
    canvas.drawRRect(
      guide,
      outline
        ..color = Colors.black54
        ..strokeWidth = 4,
    );
    canvas.drawRRect(
      guide,
      outline
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TeachGuidePainter oldDelegate) => false;
}
