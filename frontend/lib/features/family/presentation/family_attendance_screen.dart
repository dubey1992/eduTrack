import 'widgets/saved_copy_line.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
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
      return FamilyEmptyView(icon: Icons.event_available_rounded, title: context.l10n.familyNoChildrenTitle);
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
                tooltip: context.l10n.familyPreviousMonth,
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
                tooltip: context.l10n.familyNextMonth,
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
                  SavedCopyLine(name: 'attendance:${child.id}:${monthKey(_month)}'),
                  // Below the school's early-warning line (M8, 5.4): said plainly,
                  // with the figure, the same one the school sees.
                  if (data.belowLine case final below?) ...[
                    FamilyCard(
                      key: const Key('family-below-line'),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: context.appColors.warning),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.familyBelowLine(
                                '${below.rate % 1 == 0 ? below.rate.toInt() : below.rate}',
                                '${below.days}',
                                '${below.line}',
                                child.firstName,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // A parent tells the school about an absence from here (F5).
                  FamilyCard(
                    key: const Key('family-tell-absence'),
                    onTap: () => context.push('/absence-notes/new'),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.familyTellAboutAbsence,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        // May shrink and wrap: Hindi and large text both
                        // run longer than the English (M11, 3.4).
                        Flexible(
                          child: TextButton(
                            key: const Key('family-see-notes'),
                            onPressed: () => context.push('/absence-notes'),
                            child: Text(context.l10n.familyNotesSent, textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data.yearSummary != null) ...[
                    _RateCard(
                      key: const Key('family-year-rate'),
                      title: context.l10n.familyThisSchoolYear,
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
                  HowWorkedOut(key: const Key('family-why-attendance'), explanation: context.l10n.familyWhyAttendance),
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
                      ? context.l10n.familyNoRegisterYet
                      : context.l10n.familyPresentOfDays(
                              '${summary.present}',
                              '${summary.markedDays ?? summary.workingDays}',
                            ) +
                            (summary.absent > 0 ? context.l10n.familyAbsentPart(summary.absent) : '') +
                            (summary.leave > 0 ? context.l10n.familyLeavePart(summary.leave) : ''),
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                if (summary.notMarked > 0)
                  Text(
                    context.l10n.familyDaysNotMarked(summary.notMarked),
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
            for (final name in context.l10n.familyWeekdayInitials.split(' '))
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
            _Key(colour: colours.success, label: context.l10n.familyMarkPresent),
            _Key(colour: colours.danger, label: context.l10n.familyMarkAbsent),
            _Key(colour: colours.info, label: context.l10n.familyLeave),
            _Key(colour: colours.warning.withValues(alpha: 0.5), label: context.l10n.familyHoliday),
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

    final l10n = context.l10n;
    final label = switch (day.kind) {
      DayKind.present => l10n.familyDayPresent,
      DayKind.absent => l10n.familyDayAbsent,
      DayKind.leave => l10n.familyDayOnLeave,
      DayKind.holiday => day.holiday ?? l10n.familyDayHoliday,
      DayKind.closed => l10n.familyDayNoSchool,
      DayKind.future => '',
      DayKind.notMarked => l10n.familyDayNotMarked,
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
          CardHeading(icon: Icons.event_busy_rounded, title: context.l10n.familyDaysMissed),
          const SizedBox(height: 8),
          if (days.isEmpty)
            Text(context.l10n.familyNoneThisMonth, style: TextStyle(color: colours.muted))
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
                            '${day.kind == DayKind.absent ? context.l10n.familyMarkAbsent : context.l10n.familyLeave}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            day.remarks ?? context.l10n.familyNoReasonNoted,
                            style: TextStyle(color: colours.muted, fontSize: 13),
                          ),
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
