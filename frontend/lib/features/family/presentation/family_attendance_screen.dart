import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/chart_palette.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_records.dart';
import 'widgets/family_widgets.dart';

/// Attendance: a month coloured by day, the month's and the year's
/// percentage in the staff dashboard's bands (90% and above green, 75-89%
/// amber, below 75% red), and the reason for every absence.
class FamilyAttendanceScreen extends ConsumerStatefulWidget {
  const FamilyAttendanceScreen({super.key});

  @override
  ConsumerState<FamilyAttendanceScreen> createState() => _FamilyAttendanceScreenState();
}

class _FamilyAttendanceScreenState extends ConsumerState<FamilyAttendanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _step(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    if (child == null) {
      return const FamilyEmptyView(icon: Icons.event_available_rounded, title: 'No children to show');
    }

    final key = (child.id, monthKey(_month));
    final month = ref.watch(familyAttendanceProvider(key));
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                key: const Key('family-month-back'),
                tooltip: 'Previous month',
                onPressed: () => _step(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  key: const Key('family-month'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const Key('family-month-next'),
                tooltip: 'Next month',
                // No month after this one has anything to show yet.
                onPressed: _month.isBefore(thisMonth) ? () => _step(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: month.when(
            loading: () => const PlaceholderCards(count: 2),
            error: (error, _) => FamilyErrorView(
              error: error,
              onRetry: () => ref.read(familyAttendanceProvider(key).notifier).refresh(),
            ),
            data: (data) => RefreshIndicator(
              onRefresh: () => ref.read(familyAttendanceProvider(key).notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (data.yearSummary != null) ...[
                    _RateCard(
                      key: const Key('family-year-rate'),
                      title: 'This school year',
                      summary: data.yearSummary!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  FamilyCard(child: _MonthGrid(month: data)),
                  const SizedBox(height: 12),
                  _RateCard(
                    key: const Key('family-month-rate'),
                    title: DateFormat('MMMM').format(data.month),
                    summary: data.monthSummary,
                  ),
                  const SizedBox(height: 12),
                  _MissedDays(days: data.missed),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({super.key, required this.title, required this.summary});

  final String title;
  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final rate = summary.rate;
    final colour = rate == null ? muted : AttendanceBands.of(rate).colour(context);

    return FamilyCard(
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 64,
                  child: CircularProgressIndicator(
                    value: (rate ?? 0) / 100,
                    strokeWidth: 7,
                    color: colour,
                    backgroundColor: colour.withValues(alpha: 0.15),
                  ),
                ),
                Text(
                  rate == null ? '-' : '${rate.round()}%',
                  style: TextStyle(fontWeight: FontWeight.w700, color: colour),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  rate == null
                      ? 'No register marked yet.'
                      : 'Present ${summary.present} of ${summary.markedDays ?? summary.workingDays} days'
                            '${summary.absent > 0 ? ' · absent ${summary.absent}' : ''}'
                            '${summary.leave > 0 ? ' · leave ${summary.leave}' : ''}',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                if (summary.notMarked > 0)
                  Text(
                    '${summary.notMarked} school ${summary.notMarked == 1 ? 'day' : 'days'} not marked by the school',
                    key: const Key('family-not-marked'),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The month as a calendar, Monday first, each day in its colour.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month});

  final AttendanceMonth month;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final leading = month.days.first.date.weekday - 1;

    return Column(
      children: [
        Row(
          children: [
            for (final name in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    style: TextStyle(color: colours.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (final day in month.days) _DayCell(day: day, isToday: day.date == month.today),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _Key(colour: colours.success, label: 'Present'),
            _Key(colour: colours.danger, label: 'Absent'),
            _Key(colour: colours.info, label: 'Leave'),
            _Key(colour: colours.warning.withValues(alpha: 0.5), label: 'Holiday'),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.isToday});

  final AttendanceDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final (Color? fill, Color text) = switch (day.kind) {
      DayKind.present => (colours.success, Colors.white),
      DayKind.absent => (colours.danger, Colors.white),
      DayKind.leave => (colours.info, Colors.white),
      DayKind.holiday => (colours.warning.withValues(alpha: 0.25), colours.onWarningContainer),
      DayKind.closed || DayKind.future => (null, colours.muted),
      DayKind.notMarked => (Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06), colours.muted),
    };

    final label = switch (day.kind) {
      DayKind.present => 'present',
      DayKind.absent => 'absent',
      DayKind.leave => 'on leave',
      DayKind.holiday => day.holiday ?? 'holiday',
      DayKind.closed => 'no school',
      DayKind.future => '',
      DayKind.notMarked => 'not marked',
    };

    return Semantics(
      label: '${formatDate(day.date)} $label',
      excludeSemantics: true,
      child: Container(
        key: Key('family-day-${apiDate(day.date)}'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
        ),
        child: Text(
          '${day.date.day}',
          style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: context.appColors.muted)),
      ],
    );
  }
}

/// Each absence and leave this month, with the teacher's note.
class _MissedDays extends StatelessWidget {
  const _MissedDays({required this.days});

  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return FamilyCard(
      key: const Key('family-missed-days'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(icon: Icons.event_busy_rounded, title: 'Days missed'),
          const SizedBox(height: 8),
          if (days.isEmpty)
            Text('None this month.', style: TextStyle(color: colours.muted))
          else
            for (final day in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      day.kind == DayKind.absent ? Icons.cancel_rounded : Icons.event_busy_rounded,
                      size: 18,
                      color: day.kind == DayKind.absent ? colours.danger : colours.info,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat('EEEE').format(day.date)}, ${formatDate(day.date)} · '
                            '${day.kind == DayKind.absent ? 'Absent' : 'Leave'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(day.remarks ?? 'No reason noted.', style: TextStyle(color: colours.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
