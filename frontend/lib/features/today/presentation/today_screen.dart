import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../check_in/application/check_in_notifier.dart';
import '../../check_in/presentation/check_in_card.dart';
import '../../my_register/application/register_queue.dart';
import '../../staff_leave/data/models/leave_type.dart';
import '../application/today_notifier.dart';
import '../data/models/teacher_day.dart';

/// The teacher's day (docs/teacher-app.md, T1).
///
/// One call to the server, which owns the school's date, clock and calendar:
/// the periods in order with the one under way marked, the class register
/// if they are a class teacher, and what is still owed. Pull down to ask
/// again - the period under way moves on through the day.
///
/// The class register opens from its card (T2, features/my_register). A
/// period opens its report form once it has begun, or its report once
/// filed (T3, features/my_teaching).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(todayProvider);

    return RefreshIndicator(
      key: const Key('today-refresh'),
      // The check-in card asks its own endpoint; a pull refreshes both.
      onRefresh: () =>
          Future.wait([ref.read(todayProvider.notifier).refresh(), ref.read(checkInProvider.notifier).refresh()]),
      child: day.hasValue
          ? _DayView(day: day.requireValue)
          // The spinner and the error still sit in a scrollable, so a pull
          // works on them too.
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const _Greeting(date: null),
                const SizedBox(height: 16),
                AsyncValueView<TeacherDay>(
                  value: day,
                  onRetry: () => ref.read(todayProvider.notifier).retry(),
                  data: (context, value) => const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({required this.day});

  final TeacherDay day;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('today-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Greeting(date: day.date, isHalfDay: day.isOpen && day.isHalfDay),
        const SizedBox(height: 16),
        // First thing in the day, before the register and the periods.
        // It hides itself on a closed day, on leave, and where the school
        // marks staff in the office.
        const CheckInCard(),
        const SizedBox(height: 12),
        if (!day.isOpen)
          _ClosedCard(holidayName: day.holidayName)
        else ...[
          if (day.leaveToday != null) ...[_OnLeaveCard(leave: day.leaveToday!), const SizedBox(height: 12)],
          if (day.leaveToday == null) ...[_OwedLine(day: day), const SizedBox(height: 12)],
          for (final register in day.registers) ...[
            _RegisterCard(register: register, date: day.date),
            const SizedBox(height: 12),
          ],
          _SectionTitle(day.periods.isEmpty ? 'Your periods' : 'Your periods (${day.periods.length})'),
          const SizedBox(height: 8),
          if (day.periods.isEmpty)
            const _EmptyPeriods()
          else
            for (final period in day.periods) ...[
              _PeriodCard(period: period, date: day.date),
              const SizedBox(height: 8),
            ],
        ],
        if (day.otherLeaveThisWeek.isNotEmpty) ...[
          const SizedBox(height: 12),
          _LeaveThisWeek(leaves: day.otherLeaveThisWeek),
        ],
      ],
    );
  }
}

String _time(String hhmm) => formatClock(hhmm);

String _leaveLabel(String apiValue) {
  for (final type in LeaveType.values) {
    if (type.apiValue == apiValue) return type.label;
  }

  return apiValue;
}

String _span(LeaveSpan leave) => leave.startDate == leave.endDate
    ? formatDate(leave.startDate)
    : '${formatDate(leave.startDate)} to ${formatDate(leave.endDate)}';

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.date, this.isHalfDay = false});

  /// The school's date. Null while it is being fetched.
  final DateTime? date;
  final bool isHalfDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    final firstName = (user?.name ?? '').split(' ').first;
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          firstName.isEmpty ? 'Good day' : 'Good day, $firstName',
          key: const Key('today-greeting'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (date != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  DateFormat('EEEE, MMMM d, y').format(date!),
                  key: const Key('today-date'),
                  style: TextStyle(fontSize: 17, color: colors.muted),
                ),
              ),
              if (isHalfDay) ...[
                const SizedBox(width: 8),
                const StatusBadge(key: Key('today-half-day'), label: 'Half day', tone: BadgeTone.info),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({super.key, required this.icon, required this.title, required this.body, this.color});

  final IconData icon;
  final String title;
  final String body;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color ?? colors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(color: colors.muted, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.holidayName});

  final String? holidayName;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      key: const Key('today-closed'),
      icon: Icons.event_busy_outlined,
      title: holidayName == null ? 'No school today' : 'Holiday: $holidayName',
      body: 'The school is closed, so there is no register to take and no report to write.',
    );
  }
}

class _OnLeaveCard extends StatelessWidget {
  const _OnLeaveCard({required this.leave});

  final LeaveSpan leave;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      key: const Key('today-on-leave'),
      icon: Icons.beach_access_outlined,
      color: context.appColors.info,
      title: 'You are on leave today',
      body: '${_leaveLabel(leave.leaveType)}, ${_span(leave)}. Nothing is owed while you are away.',
    );
  }
}

class _OwedLine extends StatelessWidget {
  const _OwedLine({required this.day});

  final TeacherDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (day.owed == 0) {
      return Row(
        key: const Key('today-all-done'),
        children: [
          Icon(Icons.check_circle_outline, color: colors.success, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Nothing owed so far today.')),
        ],
      );
    }

    final parts = [
      if (day.registersOwed > 0) day.registersOwed == 1 ? '1 register' : '${day.registersOwed} registers',
      if (day.reportsOwed > 0) day.reportsOwed == 1 ? '1 teaching report' : '${day.reportsOwed} teaching reports',
    ];

    return Row(
      key: const Key('today-owed'),
      children: [
        Icon(Icons.pending_actions_outlined, color: colors.warning, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('Still to do: ${parts.join(' and ')}.')),
      ],
    );
  }
}

class _RegisterCard extends ConsumerWidget {
  const _RegisterCard({required this.register, required this.date});

  final ClassRegister register;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = apiDate(date);
    final queue = ref.watch(registerQueueProvider);
    // What the phone knows comes first: the server cannot know about a
    // register still waiting on this phone for signal.
    final waiting = !register.submitted && queue.waitingFor(register.classSectionId, day) != null;
    final refused = !register.submitted && !waiting && queue.unsentFor(register.classSectionId, day) != null;

    final (label, tone, hint) = register.submitted
        ? ('Taken', BadgeTone.success, 'Your class register')
        : waiting
        ? ('Saved, not sent', BadgeTone.info, 'Sends when there is signal')
        : refused
        ? ('Not sent', BadgeTone.danger, 'Tap to see why')
        : ('Not taken', BadgeTone.warning, 'Tap to take the register');

    return Card(
      key: Key('today-register-${register.classSectionId}'),
      child: ListTile(
        leading: const Icon(Icons.fact_check_outlined),
        // The class as the title and what it is beneath: on a phone the badge
        // left "Grade 8 A register" cut short.
        title: Text(register.classSection, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(hint),
        trailing: StatusBadge(label: label, tone: tone),
        onTap: () => context.push(
          Uri(
            path: '/register/${register.classSectionId}',
            queryParameters: {'date': day, 'label': register.classSection},
          ).toString(),
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.date});

  final TodayPeriod period;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isNow = period.state == PeriodState.current;

    final onTap = _openFor(context, period, date);

    return Card(
      key: Key('today-period-${period.timetableEntryId}'),
      shape: isNow
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_time(period.startTime), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(_time(period.endTime), style: TextStyle(fontSize: 12, color: colors.muted)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(period.subject, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      '${period.classSection} · Period ${period.periodNumber}',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    // Under the class rather than in a column of their own: on a
                    // phone a third column left the subject a word's width.
                    _PeriodStatus(period: period),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a period's card goes: its report once filed, the form once the
/// period has begun, nowhere before. A report about a lesson not yet given
/// is not one to write.
VoidCallback? _openFor(BuildContext context, TodayPeriod period, DateTime date) {
  if (period.reportFiled && period.reportId != null) {
    return () => context.push('/teaching/reports/${period.reportId}');
  }
  if (!period.reportOwed) return null;

  return () => context.push(
    Uri(
      path: '/teaching/report',
      queryParameters: {
        'entry': '${period.timetableEntryId}',
        'date': apiDate(date),
        'class': period.classSection,
        'subject': period.subject,
        'period': '${period.periodNumber}',
        if (period.subjectId != null) 'subject_id': '${period.subjectId}',
      },
    ).toString(),
  );
}

class _PeriodStatus extends StatelessWidget {
  const _PeriodStatus({required this.period});

  final TodayPeriod period;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (period.state == PeriodState.current) const StatusBadge(label: 'Now', tone: BadgeTone.info),
      if (period.reportFiled)
        const StatusBadge(label: 'Report filed', tone: BadgeTone.success)
      else if (period.reportOwed)
        const StatusBadge(label: 'Report owed - tap to file', tone: BadgeTone.warning),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: badges),
    );
  }
}

class _EmptyPeriods extends StatelessWidget {
  const _EmptyPeriods();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('today-no-periods'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text('You have no periods on the timetable today.', style: TextStyle(color: context.appColors.muted)),
    );
  }
}

class _LeaveThisWeek extends StatelessWidget {
  const _LeaveThisWeek({required this.leaves});

  final List<LeaveSpan> leaves;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      key: const Key('today-leave-week'),
      icon: Icons.event_note_outlined,
      title: 'Leave this week',
      body: [for (final leave in leaves) '${_leaveLabel(leave.leaveType)}, ${_span(leave)}'].join('\n'),
    );
  }
}
