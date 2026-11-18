import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/application/auth_notifier.dart';
import '../../schools/data/models/working_week.dart';
import '../../timetable/data/models/day_of_week.dart';
import '../../timetable/data/models/timetable_entry.dart';
import '../../timetable/data/timetable_repository.dart';

/// The signed-in teacher's own periods across the week - the school's
/// timetable sliced by teacher, `GET /timetable?teacher_id=<me>`
/// (docs/mobile-apps-review.md, 7.5). Read again every time it opens: the
/// office can move a period at any time.
final myWeekProvider = FutureProvider.autoDispose<List<TimetableEntry>>((ref) async {
  final me = ref.watch(authNotifierProvider).value?.id;
  if (me == null) return const [];

  return ref.read(timetableRepositoryProvider).grid(teacherId: me);
}, retry: (retryCount, error) => null);

/// "My week": a day picker opening on today, and that day's periods in bell
/// order - what Today shows for one day, for every day.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key, this.today});

  /// Which day the screen opens on; the phone's today unless a test says.
  final DateTime? today;

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  DayOfWeek? _chosen;

  @override
  Widget build(BuildContext context) {
    final week = ref.watch(myWeekProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My week')),
      body: AsyncValueView<List<TimetableEntry>>(
        value: week,
        onRetry: () => ref.invalidate(myWeekProvider),
        data: (context, entries) => _week(context, entries),
      ),
    );
  }

  Widget _week(BuildContext context, List<TimetableEntry> entries) {
    final colors = context.appColors;
    final days = {for (final entry in entries) entry.dayOfWeek}.toList()..sort((a, b) => a.index.compareTo(b.index));

    if (days.isEmpty) {
      return Center(
        key: const Key('week-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'You have no periods on the timetable yet. The office sets it up.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted),
          ),
        ),
      );
    }

    final today = DayOfWeek.values[(widget.today ?? DateTime.now()).weekday - 1];
    final day = _chosen ?? (days.contains(today) ? today : days.first);
    // A school with half days keeps a second, shorter set of periods; the
    // week shows the usual full day, and the half-day set only for a day
    // that has nothing else.
    final onDay = entries.where((entry) => entry.dayOfWeek == day).toList();
    final fullDay = onDay.where((entry) => entry.periodDayShape == WorkingWeek.fullDay).toList();
    final periods = (fullDay.isEmpty ? onDay : fullDay)..sort((a, b) => a.periodStartTime.compareTo(b.periodStartTime));

    return ListView(
      key: const Key('week-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in days)
              ChoiceChip(
                key: Key('week-day-${option.apiValue}'),
                label: Text(option == today ? '${option.label.substring(0, 3)} (today)' : option.label.substring(0, 3)),
                selected: option == day,
                onSelected: (_) => setState(() => _chosen = option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${day.label}: ${periods.length} ${periods.length == 1 ? 'period' : 'periods'}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final period in periods) ...[
          Card(
            key: Key('week-entry-${period.id}'),
            child: ListTile(
              leading: CircleAvatar(child: Text('${period.periodNumber ?? ''}')),
              title: Text(period.subjectName ?? 'Period'),
              subtitle: Text(
                [
                  ?period.classSectionName,
                  if (period.periodStartTime.isNotEmpty)
                    '${formatClock(period.periodStartTime)} - ${formatClock(period.periodEndTime)}',
                ].join(' · '),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
