import 'package:flutter/material.dart';

import '../../../../core/utils/date_format.dart';

/// The day a student joined the school. Optional: fees are charged from it,
/// and when it is left empty the server uses the day the record was added
/// (docs/fees.md, F2).
class AdmissionDateField extends StatelessWidget {
  const AdmissionDateField({super.key, required this.value, required this.onChanged, this.enabled = true});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    // The same bounds the server checks.
    final first = DateTime(1950);
    final last = today.add(const Duration(days: 365));
    final initial = value ?? today;

    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial.isBefore(first) || initial.isAfter(last) ? today : initial,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final value = this.value;

    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Admission date (optional)',
          helperText: 'Fees are charged from this date. Left empty, the day the student is added is used.',
          helperMaxLines: 2,
          suffixIcon: value != null && enabled
              ? IconButton(
                  tooltip: 'Clear admission date',
                  icon: const Icon(Icons.close),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value == null ? 'Not set' : formatDate(value)),
      ),
    );
  }
}
