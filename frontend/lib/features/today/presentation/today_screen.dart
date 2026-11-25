import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../call_requests/call_requests.dart';
import '../../my_teaching/data/outbox.dart';
import '../../my_teaching/application/staff_outbox.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/models/module_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../check_in/application/check_in_notifier.dart';
import '../../check_in/presentation/check_in_card.dart';
import '../../my_register/application/register_queue.dart';
import '../../ptm/application/ptm_providers.dart';
import '../application/today_notifier.dart';
import '../data/models/teacher_day.dart';
import 'staff_words.dart';

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
        // The rest of the week (7.5), and finding a student (7.4) for those
        // who may see students - a teacher, their own class.
        const _QuickLinks(),
        if (!day.isOpen)
          _ClosedCard(holidayName: day.holidayName)
        else ...[
          if (day.leaveToday != null) ...[_OnLeaveCard(leave: day.leaveToday!), const SizedBox(height: 12)],
          if (day.leaveToday == null) ...[_OwedLine(day: day), const SizedBox(height: 12)],
          for (final register in day.registers) ...[
            _RegisterCard(register: register, date: day.date),
            const SizedBox(height: 12),
          ],
          const _CallRequestsCard(),
          const _MeetingCard(),
          _SectionTitle(
            day.periods.isEmpty
                ? context.l10n.staffYourPeriods
                : context.l10n.staffYourPeriodsCount(day.periods.length),
          ),
          const SizedBox(height: 8),
          if (day.periods.isEmpty)
            const _EmptyPeriods()
          else
            // The teacher's periods with the school's breaks in between, in
            // the order the day rings them.
            for (final item in _inOrder(day)) ...[
              if (item is TodayPeriod) _PeriodCard(period: item, date: day.date),
              if (item is TodayBreak) _BreakLine(found: item),
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

/// Periods and breaks by start time ("08:45" sorts as text).
List<Object> _inOrder(TeacherDay day) {
  String startOf(Object item) => item is TodayPeriod ? item.startTime : (item as TodayBreak).startTime;

  return <Object>[...day.periods, ...day.breaks]..sort((a, b) => startOf(a).compareTo(startOf(b)));
}

/// A break between periods: one quiet line, marked while it is on.
class _BreakLine extends StatelessWidget {
  const _BreakLine({required this.found});

  final TodayBreak found;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final now = found.state == PeriodState.current;

    return Container(
      key: Key('today-break-${found.startTime}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.warningContainer.withValues(alpha: now ? 0.9 : 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.free_breakfast_outlined, size: 18, color: colors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              now ? context.l10n.staffBreakNow(found.name) : found.name,
              style: TextStyle(fontWeight: now ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          Text('${_time(found.startTime)} - ${_time(found.endTime)}', style: TextStyle(color: colors.muted)),
        ],
      ),
    );
  }
}

String _span(AppLocalizations l10n, LeaveSpan leave) => leave.startDate == leave.endDate
    ? formatDate(leave.startDate)
    : l10n.staffDateRange(formatDate(leave.startDate), formatDate(leave.endDate));

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
          firstName.isEmpty ? context.l10n.staffGoodDay : context.l10n.staffGoodDayName(firstName),
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
                StatusBadge(key: const Key('today-half-day'), label: context.l10n.staffHalfDay, tone: BadgeTone.info),
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
      title: holidayName == null ? context.l10n.staffNoSchoolToday : context.l10n.staffHolidayNamed(holidayName!),
      body: context.l10n.staffClosedBody,
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
      title: context.l10n.staffOnLeaveToday,
      body: context.l10n.staffOnLeaveBody(leaveTypeLabelOf(context.l10n, leave.leaveType), _span(context.l10n, leave)),
    );
  }
}

class _OwedLine extends StatelessWidget {
  const _OwedLine({required this.day});

  final TeacherDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    if (day.owed == 0) {
      return Row(
        key: const Key('today-all-done'),
        children: [
          Icon(Icons.check_circle_outline, color: colors.success, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.staffNothingOwed)),
        ],
      );
    }

    final parts = [
      if (day.registersOwed > 0) l10n.staffOwedRegisters(day.registersOwed),
      if (day.reportsOwed > 0) l10n.staffOwedReports(day.reportsOwed),
    ];

    return Row(
      key: const Key('today-owed'),
      children: [
        Icon(Icons.pending_actions_outlined, color: colors.warning, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(l10n.staffStillToDo(parts.join(l10n.staffAnd)))),
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
    final refusal = register.submitted || waiting ? null : queue.unsentFor(register.classSectionId, day)?.reason;
    final refused = refusal != null;

    final l10n = context.l10n;
    final (label, tone, hint) = register.submitted
        ? (l10n.staffRegisterTaken, BadgeTone.success, l10n.staffYourClassRegister)
        : waiting
        ? (l10n.staffSavedNotSent, BadgeTone.info, l10n.staffSendsWithSignal)
        : refused
        // The server's reason itself, so the card explains without a tap.
        ? (l10n.staffNotSent, BadgeTone.danger, refusal)
        : (l10n.staffRegisterNotTaken, BadgeTone.warning, l10n.staffTapToTakeRegister);

    return Card(
      key: Key('today-register-${register.classSectionId}'),
      child: ListTile(
        leading: const Icon(Icons.fact_check_outlined),
        // The class as the title and what it is beneath: on a phone the badge
        // left "Grade 8 A register" cut short.
        title: Text(register.classSection, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis),
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

class _QuickLinks extends ConsumerWidget {
  const _QuickLinks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;

    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 4,
        children: [
          if (user?.canView(AppModules.students) ?? false)
            TextButton.icon(
              key: const Key('today-open-students'),
              onPressed: () => context.push('/find-student'),
              icon: const Icon(Icons.person_search_outlined),
              label: Text(context.l10n.staffStudents),
            ),
          TextButton.icon(
            key: const Key('today-open-week'),
            onPressed: () => context.push('/week'),
            icon: const Icon(Icons.calendar_view_week_outlined),
            label: Text(context.l10n.staffMyWeek),
          ),
        ],
      ),
    );
  }
}

/// "2 parents asked you to call" - only while somebody is waiting
/// (docs/mobile-apps-review.md, 7.3). Nothing at all otherwise, and nothing
/// when the count cannot be read: Today is not the place for that error.
/// The next parent-teacher meeting a class of this teacher takes part in
/// (M12, 8.4). Nothing when there is none, or it cannot be read.
class _MeetingCard extends ConsumerWidget {
  const _MeetingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meeting = ref.watch(ptmNextMeetingProvider).value;
    if (meeting == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('today-meeting'),
        child: ListTile(
          leading: const Icon(Icons.groups_2_outlined),
          title: Text(context.l10n.ptmTodayCard(meeting.title, formatDate(meeting.date))),
          subtitle: Text(context.l10n.ptmTodayCardSub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await context.push('/meetings');
            ref.invalidate(ptmNextMeetingProvider);
          },
        ),
      ),
    );
  }
}

class _CallRequestsCard extends ConsumerWidget {
  const _CallRequestsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(callRequestsWaitingProvider).value ?? 0;
    if (waiting == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('today-call-requests'),
        child: ListTile(
          leading: const Icon(Icons.phone_callback_outlined),
          title: Text(context.l10n.staffParentsAskedToCall(waiting)),
          subtitle: Text(context.l10n.staffTapToSeeWho),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await context.push('/call-requests');
            ref.invalidate(callRequestsWaitingProvider);
          },
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
                      context.l10n.staffClassAndPeriod(period.classSection, period.periodNumber),
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    // Under the class rather than in a column of their own: on a
                    // phone a third column left the subject a word's width.
                    _PeriodStatus(period: period, date: date),
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
        'class_id': '${period.classSectionId}',
        if (period.subjectId != null) 'subject_id': '${period.subjectId}',
      },
    ).toString(),
  );
}

class _PeriodStatus extends ConsumerWidget {
  const _PeriodStatus({required this.period, required this.date});

  final TodayPeriod period;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // What the phone knows comes first: the server cannot know about a
    // report still waiting here for signal (2.1).
    final key = OutboxItem.reportKey(period.timetableEntryId, apiDate(date));
    final outbox = ref.watch(staffOutboxProvider);
    final waiting = !period.reportFiled && outbox.any((i) => i.key == key && i.refusal == null);
    final refused = !period.reportFiled && !waiting && outbox.any((i) => i.key == key && i.refusal != null);

    final l10n = context.l10n;
    final badges = <Widget>[
      if (period.state == PeriodState.current) StatusBadge(label: l10n.staffNow, tone: BadgeTone.info),
      if (waiting)
        StatusBadge(key: const Key('today-report-waiting'), label: l10n.staffSavedNotSent, tone: BadgeTone.info)
      else if (refused)
        StatusBadge(key: const Key('today-report-refused'), label: l10n.staffNotSentTapWhy, tone: BadgeTone.danger)
      else if (period.reportReturned)
        StatusBadge(label: l10n.staffSentBackTapChange, tone: BadgeTone.warning)
      else if (period.reportFiled)
        StatusBadge(label: l10n.staffReportFiled, tone: BadgeTone.success)
      else if (period.reportOwed)
        StatusBadge(label: l10n.staffReportOwedTapFile, tone: BadgeTone.warning),
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
      child: Text(context.l10n.staffNoPeriodsToday, style: TextStyle(color: context.appColors.muted)),
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
      title: context.l10n.staffLeaveThisWeek,
      body: [
        for (final leave in leaves)
          context.l10n.staffLeaveLine(leaveTypeLabelOf(context.l10n, leave.leaveType), _span(context.l10n, leave)),
      ].join('\n'),
    );
  }
}
