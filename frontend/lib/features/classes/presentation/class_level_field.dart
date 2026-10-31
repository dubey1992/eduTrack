import 'package:flutter/material.dart';

import '../data/class_levels.dart';

/// Picks which year of school a class is - Playgroup to Class 12 - by name,
/// never by number.
class ClassLevelField extends StatelessWidget {
  const ClassLevelField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Year',
    this.helperText,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      // A new key when the value changes from outside (worked out from the
      // name), so the field shows it.
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      items: [for (final (name, level) in standardClassLevels) DropdownMenuItem(value: level, child: Text(name))],
      onChanged: onChanged,
      validator: (v) => v == null ? 'Choose which year this is' : null,
    );
  }
}
