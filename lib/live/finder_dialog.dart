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
    this.initialName = '',
    this.storageUnavailable = false,
  });

  final CueStrings strings;
  final List<PersonalItem> items;
  final Future<String?> Function() sayName;
  final Future<void> Function(PersonalItem) removeItem;
  final void Function(String) announce;
  final String initialName;
  final bool storageUnavailable;

  @override
  State<FinderDialog> createState() => _FinderDialogState();
}

class _FinderDialogState extends State<FinderDialog> {
  CueStrings get _strings => widget.strings;
  late final _name = TextEditingController(text: widget.initialName);
  late final _items = [...widget.items];
  late String? _nameError = widget.initialName.isEmpty
      ? null
      : _strings.unrecognizedItem;
  String? _actionError;
  bool _listening = false;
  bool _removing = false;
  bool get _busy => _listening || _removing;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startSearch(String value) {
    if (_busy) return;
    final name = value.trim();
    if (taughtFinderItem(_items, name) == null &&
        builtInFinderTarget(name) == null) {
      final error = name.isEmpty
          ? _strings.itemNameNeeded
          : _strings.unrecognizedItem;
      setState(() => _nameError = error);
      widget.announce(error);
      return;
    }
    Navigator.pop(context, FinderRequest(FinderAction.find, name));
  }

  Future<void> _sayName() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _listening = true;
      _nameError = null;
    });
    final spoken = await widget.sayName();
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (spoken == null) {
        _nameError = _strings.nameNotHeard;
      } else {
        final request = FinderRequest.parse(spoken);
        _name.text =
            request != null &&
                request.action == FinderAction.find &&
                request.name.isNotEmpty
            ? request.name
            : spoken;
      }
    });
    if (spoken != null) widget.announce(_strings.heardItemName(_name.text));
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(_strings.findItem),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            enabled: !_busy,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _strings.itemName,
              errorText: _nameError,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: _startSearch,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _sayName,
            icon: const Icon(Icons.mic),
            label: Text(
              _listening ? _strings.listeningLabel : _strings.sayItemName,
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _startSearch(_name.text),
            icon: const Icon(Icons.search),
            label: Text(_strings.startSearch),
          ),
          OutlinedButton.icon(
            onPressed: _busy || widget.storageUnavailable
                ? null
                : () => Navigator.pop(
                    context,
                    FinderRequest(FinderAction.teach, _name.text.trim()),
                  ),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_strings.teachItem),
          ),
          if (widget.storageUnavailable) Text(_strings.itemStoreError),
          if (_actionError case final error?) Text(error),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(_strings.browseItems),
            children: [
              if (_items.isNotEmpty) ...[
                ListTile(title: Text(_strings.myItems)),
                for (final item in _items)
                  ListTile(
                    title: Text(item.name),
                    onTap: _busy ? null : () => _startSearch(item.name),
                    trailing: IconButton(
                      tooltip: _strings.removeItemLabel(item.name),
                      onPressed: _busy ? null : () => _removeItem(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
              ListTile(title: Text(_strings.commonItems)),
              for (final target in SearchTarget.values)
                ListTile(
                  title: Text(
                    widget.strings.language.isHindi
                        ? target.hindi
                        : target.english,
                  ),
                  onTap: _busy
                      ? null
                      : () => Navigator.pop(
                          context,
                          FinderRequest.common(target),
                        ),
                ),
            ],
          ),
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
