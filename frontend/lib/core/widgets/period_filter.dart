import 'package:flutter/material.dart';

import '../utils/date_period.dart';

/// All / Today / This week / This month, above a list (docs/teacher-app.md,
/// "Filters by period"). The same control on every list in the School365ai
/// app and on the website's staff screens, so it reads the same everywhere.
class PeriodFilter extends StatelessWidget {
  const PeriodFilter({super.key, required this.value, required this.onChanged, this.periods = DatePeriod.values});

  final DatePeriod value;
  final ValueChanged<DatePeriod> onChanged;

  /// Which periods to offer - a screen that is about one day already
  /// leaves out the ones that make no sense for it.
  final List<DatePeriod> periods;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      key: const Key('period-filter'),
      scrollDirection: Axis.horizontal,
      child: Wrap(
        spacing: 8,
        children: [
          for (final period in periods)
            ChoiceChip(
              key: Key('period-${period.name}'),
              label: Text(period.label),
              selected: value == period,
              showCheckmark: false,
              // The chosen period solid, the others quiet: the theme's own
              // chip colours read the other way round in the dark.
              selectedColor: scheme.primary,
              labelStyle: TextStyle(
                color: value == period ? scheme.onPrimary : scheme.onSurface,
                fontWeight: value == period ? FontWeight.w700 : FontWeight.w500,
              ),
              onSelected: (selected) {
                if (selected && period != value) onChanged(period);
              },
            ),
        ],
      ),
    );
  }
}
