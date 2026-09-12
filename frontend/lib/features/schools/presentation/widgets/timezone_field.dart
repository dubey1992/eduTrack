import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/timezone_list_provider.dart';
import '../../data/models/timezone_option.dart';

/// Picks the zone a school's dates and times are read in.
///
/// There are several hundred IANA zones, so the field opens a searchable
/// list rather than a dropdown to scroll: "kolkata", "pacific" or "+05:30"
/// all narrow it.
///
/// The options come from the API, so while they are loading (or if the
/// request fails) the field falls back to a plain text box rather than
/// blocking the form - a Super Admin can still type `Asia/Kolkata`, and the
/// backend validates it either way.
class TimezoneField extends ConsumerWidget {
  const TimezoneField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const helperText = 'Search by city or offset. Decides what "today" means for this school.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(timezoneListProvider)
        .when(
          loading: () => const TextField(
            enabled: false,
            decoration: InputDecoration(labelText: 'Timezone', helperText: 'Loading zones...'),
          ),
          error: (_, _) => TextFormField(
            initialValue: value,
            decoration: const InputDecoration(labelText: 'Timezone', helperText: helperText),
            onChanged: onChanged,
          ),
          data: (options) => _TimezoneTrigger(value: value, options: options, onChanged: onChanged),
        );
  }
}

/// What the form shows: the chosen zone, and a tap target that opens the
/// search. Read-only on purpose - only the picker can change it, so the field
/// can never sit there showing a half-typed search that is not what will be
/// saved.
class _TimezoneTrigger extends StatelessWidget {
  const _TimezoneTrigger({required this.value, required this.options, required this.onChanged});

  final String value;
  final List<TimezoneOption> options;
  final ValueChanged<String> onChanged;

  String get _label {
    for (final option in options) {
      if (option.name == value) return option.label;
    }

    // A zone the IANA database has since retired still shows as itself.
    return value;
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _TimezonePickerDialog(selected: value, options: options),
    );

    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Timezone',
          helperText: TimezoneField.helperText,
          prefixIcon: Icon(Icons.public, size: 20),
        ),
        child: Row(
          children: [
            Expanded(child: Text(_label, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _TimezonePickerDialog extends StatefulWidget {
  const _TimezonePickerDialog({required this.selected, required this.options});

  final String selected;
  final List<TimezoneOption> options;

  @override
  State<_TimezonePickerDialog> createState() => _TimezonePickerDialogState();
}

class _TimezonePickerDialogState extends State<_TimezonePickerDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Matches what someone would actually type: part of a city ("kolkata"), a
  /// region ("pacific"), or an offset ("+05:30"). Matching anywhere in the
  /// label matters - nobody searches for a zone by typing "Asia/".
  List<TimezoneOption> get _matches {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return widget.options;

    return widget.options.where((option) => option.label.toLowerCase().contains(term)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;

    return AlertDialog(
      title: const Text('Choose a timezone'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search',
                hintText: 'Kolkata, Pacific, +05:30',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No timezone matches that search.'))
                  // Built lazily: there are several hundred zones, and only a
                  // dozen are ever on screen.
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final option = matches[index];
                        final isSelected = option.name == widget.selected;

                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          title: Text(option.label),
                          trailing: isSelected ? const Icon(Icons.check, size: 18) : null,
                          onTap: () => Navigator.of(context).pop(option.name),
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
