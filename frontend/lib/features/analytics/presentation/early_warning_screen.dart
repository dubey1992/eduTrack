import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../schools/application/school_list_notifier.dart';
import '../application/analytics_notifier.dart';
import '../data/models/early_warning.dart';

/// Student early warning (docs/analytics.md, A3): the students whose
/// attendance or test results are low or falling, each with its reasons.
///
/// Who appears is the server's decision - an admin sees the school, a class
/// teacher their own class, a head of department the test results in their
/// subjects. This only lists what arrives, highest risk first.
class EarlyWarningScreen extends ConsumerStatefulWidget {
  const EarlyWarningScreen({super.key, this.initialLevel, this.initialSchoolId});

  /// Where the dashboard's banner opens it.
  final EarlyWarningLevel? initialLevel;
  final int? initialSchoolId;

  @override
  ConsumerState<EarlyWarningScreen> createState() => _EarlyWarningScreenState();
}

class _EarlyWarningScreenState extends ConsumerState<EarlyWarningScreen> {
  late EarlyWarningLevel? _level = widget.initialLevel;
  late int? _schoolId = widget.initialSchoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    // Who is asking decides what to ask for: nothing until that is known.
    if (actor == null) return const SizedBox.shrink();

    // Someone who spans schools looks at one at a time; their own school
    // until they pick, and a Super Admin, who has none, picks first.
    final schoolId = _schoolId ?? (actor.picksSchool ? actor.schoolId : null);
    final needsSchool = actor.picksSchool && schoolId == null;
    final schoolName = actor.picksSchool
        ? ref.watch(schoolListNotifierProvider).value?.where((school) => school.id == schoolId).firstOrNull?.name
        : null;
    final query = EarlyWarningQuery(schoolId: schoolId, level: _level, page: _page, perPage: _perPage);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Early warning', style: Theme.of(context).textTheme.headlineSmall),
              SchoolFilterDropdown(
                selected: _schoolId,
                onChanged: (id) => setState(() {
                  _schoolId = id;
                  _page = 1;
                }),
              ),
            ],
          ),
          // The branch box reads "Whole group" while this is one school's
          // list, so the school is named.
          if (_schoolId == null && actor.picksSchool && schoolName != null) ...[
            const SizedBox(height: 4),
            Text('Showing $schoolName. Pick a branch above to see another.'),
          ],
          const SizedBox(height: 4),
          Text(
            actor.role == UserRole.hod
                ? 'Students whose test results in your subjects are low or falling, and your own class in full.'
                : actor.role == UserRole.teacher
                ? 'Students in your class whose attendance or test results are low or falling.'
                : 'Students whose attendance or test results are low or falling, with the reasons.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (needsSchool)
            const _Notice('Pick a school to see its students.')
          else
            AsyncValueView<EarlyWarningPage>(
              value: ref.watch(earlyWarningProvider(query)),
              onRetry: () => ref.invalidate(earlyWarningProvider(query)),
              data: (context, page) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Filters(
                    summary: page.summary,
                    selected: _level,
                    onSelected: (level) => setState(() {
                      _level = level;
                      _page = 1;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _Rules(summary: page.summary),
                  const SizedBox(height: 16),
                  if (page.students.isEmpty)
                    _Notice(
                      _level == null
                          ? 'No students are flagged. Nobody is under the lines above, or down by '
                                '${page.summary.dropPoints} points or more.'
                          : 'No students at this level.',
                    )
                  else ...[
                    for (final student in page.students) ...[
                      _StudentCard(student: student),
                      const SizedBox(height: 10),
                    ],
                    PaginationControls(
                      currentPage: page.currentPage,
                      lastPage: page.lastPage,
                      total: page.total,
                      perPage: page.perPage,
                      onPageChanged: (value) => setState(() => _page = value),
                      onPerPageChanged: (value) => setState(() {
                        _perPage = value;
                        _page = 1;
                      }),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.summary, required this.selected, required this.onSelected});

  final EarlyWarningSummary summary;
  final EarlyWarningLevel? selected;
  final ValueChanged<EarlyWarningLevel?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text('All flagged (${summary.flaggedCount})'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        ChoiceChip(
          label: Text('${EarlyWarningLevel.high.label} (${summary.highCount})'),
          selected: selected == EarlyWarningLevel.high,
          onSelected: (_) => onSelected(EarlyWarningLevel.high),
        ),
        ChoiceChip(
          label: Text('${EarlyWarningLevel.atRisk.label} (${summary.atRiskCount})'),
          selected: selected == EarlyWarningLevel.atRisk,
          onSelected: (_) => onSelected(EarlyWarningLevel.atRisk),
        ),
      ],
    );
  }
}

/// The lines the list was drawn with, stated - a flag nobody can check is
/// a flag nobody should act on.
class _Rules extends StatelessWidget {
  const _Rules({required this.summary});

  final EarlyWarningSummary summary;

  @override
  Widget build(BuildContext context) {
    return Text(
      'As of ${formatIsoDate(summary.asOf)}. Flagged for attendance under ${summary.attendanceBelow}% over the '
      'last 30 school days, a test average under the ${summary.passMark}% pass mark over the last 90 days, or a '
      'fall of ${summary.dropPoints} points or more in either. One reason is "at risk", two or more "high risk". '
      'A School Admin sets these lines in Module Settings, under Reports.',
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student});

  final FlaggedStudent student;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final high = student.level == EarlyWarningLevel.high;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(student.name, style: Theme.of(context).textTheme.titleMedium),
                StatusBadge(label: student.level.label, tone: high ? BadgeTone.danger : BadgeTone.warning),
                Text(
                  [?student.classSection, ?student.admissionNumber].join(' · '),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final signal in student.signals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      signal.isAttendance ? Icons.event_busy_outlined : Icons.trending_down,
                      size: 18,
                      color: high ? scheme.error : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(signal.message)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}
