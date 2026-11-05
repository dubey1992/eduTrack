import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/viewed_year.dart';
import '../data/models/academic_year.dart';

/// The top bar's academic-year switch (decided 2026-11-05). Every
/// year-based screen follows it; a year other than the current one is
/// marked, so nobody mistakes last year's figures for this year's.
///
/// Only for somebody who works in one school - a Super Admin or a group
/// looking across schools picks the school on each screen first, and the
/// years differ from one school to the next.
class YearSwitch extends ConsumerWidget {
  const YearSwitch({super.key, this.compact = false});

  /// The phone's app bar: the year alone, no "Year" caption.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    if (user == null || user.schoolId == null || user.picksSchool) return const SizedBox.shrink();

    final years = ref.watch(schoolYearsProvider).value;
    final viewed = ref.watch(viewedYearProvider).value;
    if (years == null || years.isEmpty || viewed == null) return const SizedBox.shrink();

    final standing = standingOf(viewed, years);
    final colours = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (standing) {
      YearStanding.current => (scheme.surfaceContainerHighest, scheme.onSurface),
      YearStanding.past => (colours.warningContainer, colours.onWarningContainer),
      YearStanding.next => (colours.infoContainer, colours.onInfoContainer),
    };

    return PopupMenuButton<int>(
      key: const Key('year-switch'),
      tooltip: 'Academic year shown on every screen',
      onSelected: (id) => ref.read(viewedYearIdProvider.notifier).choose(_isCurrent(id, years) ? null : id),
      itemBuilder: (context) => [
        for (final year in years)
          CheckedPopupMenuItem<int>(
            value: year.id,
            checked: year.id == viewed.id,
            child: Text('${year.name}${_suffix(standingOf(year, years))}'),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              compact ? viewed.name : 'Year ${viewed.name}${_suffix(standing)}',
              key: const Key('year-switch-label'),
              style: TextStyle(fontWeight: FontWeight.w600, color: foreground),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }

  static bool _isCurrent(int id, List<AcademicYear> years) => years.any((year) => year.id == id && year.isCurrent);

  static String _suffix(YearStanding standing) => switch (standing) {
    YearStanding.current => ' (current)',
    YearStanding.past => ' (past year)',
    YearStanding.next => ' (next year)',
  };
}
