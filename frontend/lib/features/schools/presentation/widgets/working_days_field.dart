import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/working_week.dart';

/// Picks the days a school actually runs (docs/holidays.md).
///
/// Seven toggles rather than a dropdown of named weeks, because the weeks
/// schools keep do not come from a short list: Monday to Friday, Sunday to
/// Thursday, six days, and six days with a different one off are all
/// ordinary somewhere.
///
/// It decides more than it looks like it decides. Attendance is refused on a
/// day the school does not run, no period is taught, no bus goes, and every
/// rate in every report is out of the days that are left — so the field says
/// so rather than sitting there as an unexplained row of chips.
class WorkingDaysField extends StatelessWidget {
  const WorkingDaysField({super.key, required this.value, required this.onChanged});

  final WorkingWeek value;
  final ValueChanged<WorkingWeek> onChanged;

  static const helperText = 'Attendance, periods, buses and every report rate follow these days.';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Working days', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var index = 0; index < WorkingWeek.names.length; index++)
              FilterChip(
                // A half day is marked on the chip, not only in the line
                // underneath: it looks exactly like a full day otherwise,
                // and turning one off and on again quietly makes it full.
                label: Text(
                  value.isHalfDay(index) ? '${WorkingWeek.shortLabels[index]} ½' : WorkingWeek.shortLabels[index],
                ),
                tooltip: value.isHalfDay(index) ? '${WorkingWeek.labels[index]} - half day' : WorkingWeek.labels[index],
                selected: value.runsOn(index),
                onSelected: (_) => onChanged(value.toggled(index)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          // The summary is the part somebody reads back to check: seven
          // chips are easy to mis-tap and hard to re-read, and "Sunday to
          // Thursday" is unmistakable.
          value.isEmpty ? 'Pick at least one day.' : '${value.summary}. $helperText',
          style: theme.textTheme.bodySmall?.copyWith(color: value.isEmpty ? colors.danger : colors.muted),
        ),
        // Said on its own line because a range like "Monday to Saturday" is
        // true and still hides the part somebody most needs to check.
        if (value.halfDayNote case final note?)
          Text(note, style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
      ],
    );
  }
}
