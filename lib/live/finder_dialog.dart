import 'package:flutter/material.dart';

import '../core/cue_language.dart';
import '../core/cue_strings.dart';
import '../core/finder_request.dart';
import '../core/personal_items.dart';
import '../core/search_target.dart';

class FinderDialog extends StatefulWidget {
  const FinderDialog({
    super.key,
    required this.strings,
    required this.items,
    required this.sayName,
    required this.removeItem,
    required this.announce,
    this.volumeShortcut,
    this.storageUnavailable = false,
  });

  final CueStrings strings;
  final List<PersonalItem> items;
  final Future<String?> Function() sayName;
  final Future<void> Function(PersonalItem) removeItem;
  final void Function(String) announce;
  final Listenable? volumeShortcut;
  final bool storageUnavailable;

  @override
  State<FinderDialog> createState() => _FinderDialogState();
}

class _FinderDialogState extends State<FinderDialog> {
  CueStrings get _strings => widget.strings;
  final _name = TextEditingController();
  late final _items = [...widget.items];
  String? _unknownName;
  String? _nameError;
  String? _actionError;
  bool _listening = false;
  bool _removing = false;
  bool get _busy => _listening || _removing;

  @override
  void initState() {
    super.initState();
    widget.volumeShortcut?.addListener(_sayName);
  }

  @override
  void dispose() {
    widget.volumeShortcut?.removeListener(_sayName);
    _name.dispose();
    super.dispose();
  }

  void _startSearch(String value) {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final name = value.trim();
    if (taughtFinderItem(_items, name) == null &&
        builtInFinderTarget(name) == null) {
      final error = name.isEmpty
          ? _strings.itemNameNeeded
          : _strings.unrecognizedItem;
      setState(() {
        _nameError = error;
        _unknownName = name.isEmpty ? null : name;
      });
      widget.announce(error);
      return;
    }
    Navigator.pop(context, FinderRequest(FinderAction.find, name));
  }

  Future<void> _sayName() async {
    if (_busy || ModalRoute.of(context)?.isCurrent != true) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _listening = true;
      _nameError = null;
      _unknownName = null;
    });
    final spoken = await widget.sayName();
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() {
      _listening = false;
      if (spoken == null) _nameError = _strings.nameNotHeard;
    });
    if (spoken == null) return;
    final request = FinderRequest.parse(spoken);
    if (request?.action == FinderAction.teach) {
      if (widget.storageUnavailable) {
        widget.announce(_strings.itemStoreError);
      } else {
        Navigator.pop(context, request);
      }
      return;
    }
    final name = request?.name ?? spoken;
    _name.text = name;
    _startSearch(name);
  }

  Future<void> _removeItem(PersonalItem item) async {
    setState(() {
      _removing = true;
      _actionError = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_strings.removeItemQuestion(item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_strings.removeItem),
          ),
        ],
      ),
    );
    if (!mounted) return;
    try {
      if (confirmed == true) {
        await widget.removeItem(item);
        if (!mounted) return;
        setState(() => _items.remove(item));
        widget.announce(_strings.itemRemoved(item.name));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = _strings.itemRemoveError);
      widget.announce(_strings.itemRemoveError);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Widget _builtInItemButton(SearchTarget target) => OutlinedButton(
    onPressed: _busy
        ? null
        : () => Navigator.pop(context, FinderRequest.common(target)),
    child: Text(_strings.language.isHindi ? target.hindi : target.english),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(_strings.findItem),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            autofocus: true,
            onPressed: _busy ? null : _sayName,
            icon: const Icon(Icons.mic),
            label: Text(
              _listening ? _strings.listeningLabel : _strings.sayWhatToFind,
            ),
          ),
          if (_nameError case final error?) Text(error),
          if (_unknownName case final name? when !widget.storageUnavailable)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(
                      context,
                      FinderRequest(FinderAction.teach, name),
                    ),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_strings.teachingItem(name)),
            ),
          const SizedBox(height: 12),
          Semantics(header: true, child: Text(_strings.commonItems)),
          Wrap(
            spacing: 8,
            children: [
              for (final target in SearchTarget.quickChoices)
                _builtInItemButton(target),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(_strings.moreCommonItems),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final target in SearchTarget.values)
                    if (!SearchTarget.quickChoices.contains(target))
                      _builtInItemButton(target),
                ],
              ),
            ],
          ),
          if (_unknownName == null && !widget.storageUnavailable)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(
                      context,
                      const FinderRequest(FinderAction.teach, ''),
                    ),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_strings.teachItem),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(_strings.typeItemName),
            children: [
              TextField(
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: _strings.itemName),
                onSubmitted: _startSearch,
              ),
              TextButton(
                onPressed: _busy ? null : () => _startSearch(_name.text),
                child: Text(_strings.startSearch),
              ),
            ],
          ),
          if (widget.storageUnavailable) Text(_strings.itemStoreError),
          if (_actionError case final error?) Text(error),
          if (_items.isNotEmpty) ...[
            Semantics(header: true, child: Text(_strings.myItems)),
            for (final item in _items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                onTap: _busy ? null : () => _startSearch(item.name),
                trailing: IconButton(
                  tooltip: _strings.removeItemLabel(item.name),
                  onPressed: _busy ? null : () => _removeItem(item),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_strings.cancel),
        ),
      ],
    );
  }
}
