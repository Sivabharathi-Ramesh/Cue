import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../core/cue_strings.dart';
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
    this.initialName = '',
  });

  final CueStrings strings;
  final ValueListenable<CameraController?> camera;
  final List<PersonalItem> items;
  final Future<String?> Function() sayName;
  final Future<PersonalExample> Function() capture;
  final Future<void> Function(PersonalItem) save;
  final void Function(String) announce;
  final String initialName;

  @override
  State<TeachItemDialog> createState() => _TeachItemDialogState();
}

class _TeachItemDialogState extends State<TeachItemDialog> {
  CueStrings get _strings => widget.strings;
  late final _name = TextEditingController(text: widget.initialName);
  final _examples = <PersonalExample>[];
  String? _profileName;
  String? _error;
  bool _listening = false;
  bool _working = false;
  bool _saving = false;
  bool get _busy => _listening || _working || _saving;
  bool get _readyToSave => _examples.length == PersonalItem.examplesToTeach;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _report(String error) {
    setState(() => _error = error);
    widget.announce(error);
  }

  void _announceStep() =>
      widget.announce(_strings.teachingPrompt(_examples.length));

  Future<void> _sayName() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _listening = true;
      _error = null;
    });
    final name = await widget.sayName();
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (name == null) {
        _error = _strings.nameNotHeard;
      } else {
        _name.text = name;
      }
    });
    if (name != null) widget.announce(_strings.heardItemName(name));
  }

  Future<void> _continue() async {
    if (_busy) return;
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
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_strings.replaceItemQuestion(name)),
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
      if (!mounted) return;
      setState(() => _working = false);
      if (replace != true) return;
    }
    setState(() {
      _profileName = name;
      _error = null;
    });
    _announceStep();
  }

  Future<void> _capture() async {
    if (_busy || _readyToSave) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final example = await widget.capture();
      if (!mounted || !ModalRoute.of(context)!.isCurrent) return;
      if (_examples.isNotEmpty &&
          !_examples.any(
            (saved) =>
                saved.format == example.format &&
                embeddingSimilarity(saved.foreground, example.foreground) >=
                    0.55,
          )) {
        _report(_strings.itemCaptureDifferent);
        return;
      }
      setState(() => _examples.add(example));
      HapticFeedback.selectionClick();
      _announceStep();
    } on UnclearPersonalExample {
      if (mounted) _report(_strings.itemCaptureUnclear);
    } catch (_) {
      if (mounted) _report(_strings.itemCaptureError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _retake() {
    setState(() {
      _examples.removeLast();
      _error = null;
    });
    _announceStep();
  }

  Future<void> _save() async {
    if (_busy || !_readyToSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = PersonalItem(_profileName!, _examples);
      await widget.save(item);
      if (mounted) Navigator.pop(context, item);
    } catch (_) {
      if (mounted) _report(_strings.itemSaveError);
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
      TextField(
        controller: _name,
        enabled: !_busy,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _continue(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: _strings.itemName,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _sayName,
        icon: const Icon(Icons.mic),
        label: Text(
          _listening ? _strings.listeningLabel : _strings.sayItemName,
        ),
      ),
      FilledButton(
        onPressed: _busy ? null : _continue,
        child: Text(_strings.next),
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
      Text(_strings.teachingPrompt(_examples.length)),
      if (!_readyToSave) _preview(),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 12),
      if (_readyToSave)
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_saving ? _strings.savingItem : _strings.saveItem),
        )
      else
        FilledButton.icon(
          onPressed: _busy ? null : _capture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(
            _working ? _strings.capturingExample : _strings.captureExample,
          ),
        ),
      if (_examples.isNotEmpty)
        TextButton(
          onPressed: _busy ? null : _retake,
          child: Text(_strings.retakeExample),
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
