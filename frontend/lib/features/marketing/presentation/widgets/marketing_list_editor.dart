import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/live_figures.dart';
import '../../data/models/marketing_draft.dart';

/// One repeating list on the homepage - the feature cards, the figures
/// under the hero, the ticked list, a footer column.
///
/// Each row owns its own text controllers, and moving a row moves that
/// object rather than copying strings between boxes. Without it, reordering
/// while somebody is typing drops their cursor to the end of a different
/// row's text.
///
/// The list the page ships with is what this starts from when nobody has
/// changed it, and "Use the ones that ship" puts it back - the equivalent
/// of clearing a box, which for a whole list has to be an action.
class MarketingListEditor extends StatefulWidget {
  const MarketingListEditor({
    super.key,
    required this.declared,
    required this.initial,
    required this.onChanged,
    required this.enabled,
    this.serverError,
    this.figures = const {},
  });

  final MarketingListField declared;
  final List<Map<String, String>> initial;
  final ValueChanged<List<Map<String, String>>> onChanged;
  final bool enabled;
  final String? serverError;

  /// What a live figure would say today. Only the hero's figures use it.
  final Map<String, int> figures;

  @override
  State<MarketingListEditor> createState() => _MarketingListEditorState();
}

class _MarketingListEditorState extends State<MarketingListEditor> {
  final _rows = <_Row>[];

  /// Only ever counts up, so no two rows share a key even after one is
  /// removed and another added in its place.
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _fill(widget.initial);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _fill(List<Map<String, String>> items) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(items.map((item) => _Row(id: _nextId++, declared: widget.declared, values: item)));
  }

  void _report() => widget.onChanged([for (final row in _rows) row.values]);

  void _add() {
    setState(() => _rows.add(_Row(id: _nextId++, declared: widget.declared, values: widget.declared.blankItem)));
    _report();
  }

  void _remove(int index) {
    setState(() => _rows.removeAt(index).dispose());
    _report();
  }

  void _move(int index, int by) {
    setState(() => _rows.insert(index + by, _rows.removeAt(index)));
    _report();
  }

  void _revert() {
    setState(() => _fill(widget.declared.shipped));
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final full = _rows.length >= widget.declared.maxItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.declared.label, style: Theme.of(context).textTheme.titleSmall)),
            TextButton.icon(
              onPressed: widget.enabled ? _revert : null,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Use the ones that ship'),
            ),
          ],
        ),
        if (widget.declared.help.isNotEmpty)
          Text(widget.declared.help, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
        if (widget.serverError != null) ...[
          const SizedBox(height: 8),
          Text(widget.serverError!, style: TextStyle(color: colors.danger)),
        ],
        for (var index = 0; index < _rows.length; index++) ...[
          const SizedBox(height: 12),
          _ItemCard(
            key: ValueKey(_rows[index].id),
            row: _rows[index],
            position: index,
            count: _rows.length,
            itemLabel: widget.declared.itemLabel,
            figures: widget.figures,
            enabled: widget.enabled,
            canRemove: _rows.length > widget.declared.minItems,
            onChanged: _report,
            onRemove: () => _remove(index),
            onMoveUp: index == 0 ? null : () => _move(index, -1),
            onMoveDown: index == _rows.length - 1 ? null : () => _move(index, 1),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: widget.enabled && !full ? _add : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add ${widget.declared.itemLabel.toLowerCase()}'),
            ),
            const SizedBox(width: 12),
            Text(
              full
                  ? '${widget.declared.maxItems} is as many as the design holds.'
                  : '${_rows.length} of ${widget.declared.maxItems}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    super.key,
    required this.row,
    required this.position,
    required this.count,
    required this.itemLabel,
    required this.figures,
    required this.enabled,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final _Row row;
  final int position;
  final int count;
  final String itemLabel;
  final Map<String, int> figures;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

/// Stateful only so that choosing a source redraws the line beneath it -
/// the line says what that source reads today, and a picker whose caption
/// does not follow the choice is worse than no caption.
class _ItemCardState extends State<_ItemCard> {
  _Row get row => widget.row;
  String get itemLabel => widget.itemLabel;
  Map<String, int> get figures => widget.figures;
  bool get enabled => widget.enabled;
  int get position => widget.position;
  int get count => widget.count;
  bool get canRemove => widget.canRemove;
  VoidCallback get onRemove => widget.onRemove;
  VoidCallback? get onMoveUp => widget.onMoveUp;
  VoidCallback? get onMoveDown => widget.onMoveDown;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$itemLabel ${position + 1} of $count',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.muted),
                ),
              ),
              IconButton(
                onPressed: enabled ? onMoveUp : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: 'Move $itemLabel ${position + 1} up',
              ),
              IconButton(
                onPressed: enabled ? onMoveDown : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: 'Move $itemLabel ${position + 1} down',
              ),
              IconButton(
                // The last one cannot go: an empty grid is a hole in the
                // page, and the server refuses it anyway.
                onPressed: enabled && canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: canRemove
                    ? 'Remove $itemLabel ${position + 1}'
                    : 'The page needs at least one ${itemLabel.toLowerCase()}',
              ),
            ],
          ),
          for (final field in row.declared.fields) ...[
            const SizedBox(height: 8),
            if (field.choices.isEmpty)
              TextFormField(
                controller: row.controllers[field.key],
                enabled: enabled,
                maxLength: field.maxLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                decoration: InputDecoration(
                  labelText: field.label,
                  helperText: field.help.isEmpty ? null : field.help,
                  helperMaxLines: 2,
                  isDense: true,
                ),
                onChanged: (value) {
                  row.values[field.key] = value;
                  widget.onChanged();
                },
                validator: (value) => _problemWith(field, value ?? ''),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _pick(field, row.values[field.key]),
                decoration: InputDecoration(
                  labelText: field.label,
                  // What a live figure reads today, so somebody can see the
                  // real number before putting it on the front page.
                  helperText: _reading(field, row) ?? (field.help.isEmpty ? null : field.help),
                  helperMaxLines: 2,
                  isDense: true,
                ),
                items: [
                  for (final choice in field.choices)
                    DropdownMenuItem(value: choice.value, child: Text(_choiceLabel(choice))),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value == null) return;
                        setState(() => row.values[field.key] = value);
                        widget.onChanged();
                      }
                    : null,
              ),
          ],
        ],
      ),
    );
  }

  /// A value short enough to be a symbol is shown beside its name, because
  /// the symbol is the thing being chosen - that is how the icon picker
  /// reads. A value that is a word is a key, which nobody should see.
  String _choiceLabel(MarketingChoice choice) {
    return choice.value.characters.length <= 2 ? '${choice.value}   ${choice.label}' : choice.label;
  }

  /// The line under a source picker: what it would say if published now,
  /// or that there is nothing to count yet - which is the thing somebody
  /// most needs to know before choosing it.
  String? _reading(MarketingItemField field, _Row row) {
    if (field.key != statSourceKey) return null;

    final source = row.values[field.key];

    if (source == null || source == typedSource) return null;

    final reading = liveReading(source, figures);

    return reading == null
        ? 'Nothing to count yet - the figure below is what visitors will see.'
        : 'Shows $reading right now.';
  }

  /// A value saved before the set changed is not on the picker any more;
  /// falling back keeps the dropdown from throwing on a stale document.
  String? _pick(MarketingItemField field, String? value) {
    if (field.choices.any((choice) => choice.value == value)) return value;

    return field.choices.isEmpty ? null : field.choices.first.value;
  }

  String? _problemWith(MarketingItemField field, String value) {
    final text = value.trim();

    if (text.isEmpty) {
      // Unlike a page-level box, a blank required one is not a fallback to
      // anything: a card with no title is a hole in the grid. An optional
      // box left empty is a choice, and the commonest one.
      return field.required ? 'Every $itemLabel needs a ${field.label.toLowerCase()}.' : null;
    }

    if (text.length > field.maxLength) {
      return '${field.label} must be ${field.maxLength} characters or fewer - it is ${text.length}.';
    }

    return null;
  }
}

/// One item, and the boxes it is edited in. The controllers belong to the
/// row so they travel with it when it is moved.
class _Row {
  _Row({required this.id, required this.declared, required Map<String, String> values})
    : values = {for (final field in declared.fields) field.key: values[field.key] ?? ''},
      controllers = {
        for (final field in declared.fields)
          if (field.choices.isEmpty) field.key: TextEditingController(text: values[field.key] ?? ''),
      };

  final int id;
  final MarketingListField declared;
  final Map<String, String> values;
  final Map<String, TextEditingController> controllers;

  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}
