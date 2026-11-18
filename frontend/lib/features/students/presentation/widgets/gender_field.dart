import 'package:flutter/material.dart';

import '../../data/models/student.dart';

/// A student's gender, optional (docs/dashboard.md). "Not given" is a real
/// choice, not an error: the dashboard counts it beside "other", so boys,
/// girls and the rest always add up to the roll.
class GenderField extends StatelessWidget {
  const GenderField({super.key, required this.value, required this.onChanged});

  final StudentGender? value;
  final ValueChanged<StudentGender?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<StudentGender?>(
      key: const Key('student-gender'),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Gender (optional)'),
      items: [
        const DropdownMenuItem<StudentGender?>(value: null, child: Text('Not given')),
        for (final gender in StudentGender.values)
          DropdownMenuItem<StudentGender?>(value: gender, child: Text(gender.label)),
      ],
      onChanged: onChanged,
    );
  }
}
