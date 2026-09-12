import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "‹ September 2026 ›" - steps one calendar month at a time. [month] is
/// always the first day of a month; stepping forward stops at [maxMonth],
/// since there is no data in the future.
///
/// [maxMonth] is required rather than defaulting to the current month: only
/// the caller knows whose month that is, and for a school abroad it is not
/// necessarily the browser's.
class MonthStepper extends StatelessWidget {
  const MonthStepper({super.key, required this.month, required this.onChanged, required this.maxMonth});

  final DateTime month;
  final DateTime maxMonth;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final canGoForward = month.isBefore(maxMonth);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        SizedBox(
          width: 150,
          child: Text(
            DateFormat.yMMMM().format(month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          onPressed: canGoForward ? () => onChanged(DateTime(month.year, month.month + 1)) : null,
        ),
      ],
    );
  }
}
