import 'package:flutter/material.dart';

/// A dropdown that can be searched once its list is long (asked for
/// 2026-11-05: "it's difficult to find the exact value").
///
/// A short list - a handful of statuses, three terms - stays the ordinary
/// dropdown, where scanning beats typing. From [searchFrom] options on, the
/// field opens the app's own picker instead: a search box over the list,
/// narrowing as you type, matched anywhere in the option's text and without
/// regard to case.
///
/// Takes what the screens already pass to DropdownButtonFormField, so a
/// screen changes the one class name.
class SearchableDropdown<T> extends StatelessWidget {
  const SearchableDropdown({
    super.key,
    required this.items,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.validator,
    this.isExpanded = true,
    this.searchFrom = 9,
  });

  final List<DropdownMenuItem<T>> items;
  final T? initialValue;
  final InputDecoration decoration;

  /// Null disables the field, as it does a DropdownButtonFormField.
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;
  final bool isExpanded;

  /// How many options make a list long enough to search.
  final int searchFrom;

  @override
  Widget build(BuildContext context) {
    if (items.length < searchFrom) {
      return DropdownButtonFormField<T>(
        initialValue: items.any((item) => item.value == initialValue) ? initialValue : null,
        isExpanded: isExpanded,
        decoration: decoration,
        items: items,
        onChanged: onChanged,
        validator: validator,
      );
    }

    // Keyed on the value so a new one from the screen is shown, as the
    // ordinary dropdown does.
    return _SearchField<T>(
      key: ValueKey<Object?>(initialValue),
      items: items,
      initialValue: initialValue,
      decoration: decoration,
      onChanged: onChanged,
      validator: validator,
    );
  }
}

/// What an option says, for matching and for showing once chosen.
String _labelOf<T>(DropdownMenuItem<T> item) {
  final child = item.child;
  if (child is Text) return child.data ?? child.textSpan?.toPlainText() ?? '';
  if (child is RichText) return child.text.toPlainText();

  return '${item.value}';
}

class _SearchField<T> extends StatelessWidget {
  const _SearchField({
    super.key,
    required this.items,
    required this.initialValue,
    required this.decoration,
    required this.onChanged,
    required this.validator,
  });

  final List<DropdownMenuItem<T>> items;
  final T? initialValue;
  final InputDecoration decoration;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: items.any((item) => item.value == initialValue) ? initialValue : null,
      validator: validator,
      builder: (field) {
        final chosen = items.where((item) => item.value == field.value).firstOrNull;
        final enabled = onChanged != null;

        return InkWell(
          key: const Key('searchable-dropdown'),
          onTap: enabled
              ? () async {
                  final picked = await showDialog<_Picked<T>>(
                    context: context,
                    builder: (_) =>
                        _SearchDialog<T>(title: decoration.labelText ?? 'Choose', items: items, selected: field.value),
                  );
                  if (picked == null) return;
                  field.didChange(picked.value);
                  onChanged!(picked.value);
                }
              : null,
          child: InputDecorator(
            decoration: decoration.copyWith(
              errorText: field.errorText,
              enabled: enabled,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            isEmpty: chosen == null,
            child: chosen == null
                ? const SizedBox.shrink()
                : Text(_labelOf(chosen), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}

/// A choice from the picker - wrapped, so choosing a null option is not
/// mistaken for closing the picker without choosing.
class _Picked<T> {
  const _Picked(this.value);

  final T? value;
}

class _SearchDialog<T> extends StatefulWidget {
  const _SearchDialog({required this.title, required this.items, required this.selected});

  final String title;
  final List<DropdownMenuItem<T>> items;
  final T? selected;

  @override
  State<_SearchDialog<T>> createState() => _SearchDialogState<T>();
}

class _SearchDialogState<T> extends State<_SearchDialog<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final words = _query.toLowerCase().split(' ').where((word) => word.isNotEmpty);
    final shown = [
      for (final item in widget.items)
        if (words.every((word) => _labelOf(item).toLowerCase().contains(word))) item,
    ];

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('searchable-dropdown-search'),
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing matches "$_query".',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final item = shown[index];
                        final isSelected = item.value == widget.selected;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          enabled: item.enabled,
                          title: item.child,
                          trailing: isSelected ? const Icon(Icons.check, size: 18) : null,
                          onTap: () => Navigator.of(context).pop(_Picked<T>(item.value)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}
