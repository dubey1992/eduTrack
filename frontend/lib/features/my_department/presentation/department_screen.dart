import '../../staff_leave/data/staff_leave_repository.dart';
import '../../staff_leave/data/models/staff_leave.dart';
import '../../staff_attendance/presentation/save_staff_register.dart';
import '../../staff_attendance/application/staff_attendance_register_notifier.dart';
import '../../auth/application/auth_notifier.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/models/module_access.dart';
import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/date_period.dart';
import '../../../core/widgets/period_filter.dart';
import '../../reports/data/models/report.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../hod/data/models/hod_department_report.dart';
import '../../staff_attendance/data/models/staff_attendance_register.dart';
import '../../staff_attendance/data/models/staff_attendance_status.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../application/department_providers.dart';
import '../../today/presentation/staff_words.dart';

/// The Department tab, for an HOD (docs/teacher-app.md, T7): the reports
/// waiting for their review, the department's leave to decide, who is in
/// today - marked here too (docs/mobile-apps-review.md, 7.1) - and how each
/// teacher's month is going.
class DepartmentScreen extends ConsumerWidget {
  const DepartmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    // Leave is decided where the role may manage it - an HOD, by default.
    final decidesLeave = user?.canManage(AppModules.leave) ?? false;
    final l10n = context.l10n;

    return DefaultTabController(
      length: decidesLeave ? 4 : 3,
      child: Column(
        children: [
          TabBar(
            key: const Key('department-tabs'),
            tabs: [
              Tab(key: const Key('department-tab-review'), text: l10n.staffTabToReview),
              if (decidesLeave) Tab(key: const Key('department-tab-leave'), text: l10n.staffNavLeave),
              Tab(key: const Key('department-tab-staff'), text: l10n.staffTabStaff),
              Tab(key: const Key('department-tab-month'), text: l10n.staffTabTeachers),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [const _ReviewTab(), if (decidesLeave) const _LeaveTab(), const _StaffTab(), const _MonthTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: context.appColors.muted));
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: colors.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

// -- To review ----------------------------------------------------------------

class _ReviewTab extends ConsumerWidget {
  const _ReviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider);
    final notifier = ref.read(reviewQueueProvider.notifier);
    final l10n = context.l10n;

    return RefreshIndicator(
      key: const Key('review-refresh'),
      onRefresh: () => ref.read(reviewQueueProvider.notifier).refresh(),
      child: ListView(
        key: const Key('review-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _Intro(l10n.staffReviewIntro),
          const SizedBox(height: 12),
          PeriodFilter(value: notifier.period, onChanged: notifier.setPeriod),
          const SizedBox(height: 16),
          if (!queue.hasValue)
            AsyncValueView<ReviewQueue>(
              value: queue,
              onRetry: () => ref.read(reviewQueueProvider.notifier).retry(),
              data: (context, value) => const SizedBox.shrink(),
            )
          else if (queue.requireValue.items.isEmpty)
            _Empty(
              key: const Key('review-empty'),
              icon: Icons.task_alt,
              title: l10n.staffReviewEmpty(notifier.period.name),
              body: l10n.staffReviewEmptyBody,
            )
          else ...[
            for (final report in queue.requireValue.items) ...[_ReviewCard(report: report), const SizedBox(height: 10)],
            if (queue.requireValue.hasMore)
              Center(
                child: TextButton(
                  key: const Key('review-more'),
                  onPressed: () => ref.read(reviewQueueProvider.notifier).loadMore(),
                  child: Text(l10n.staffShowMore),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final where = [
      report.subjectName,
      report.classSectionName,
      if (report.periodNumber != null) context.l10n.staffPeriodNumber(report.periodNumber!),
    ].whereType<String>().join(' · ');

    return Card(
      key: Key('review-${report.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/teaching/reports/${report.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.teacherName ?? context.l10n.staffATeacher,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(formatIsoDate(report.reportDate), style: TextStyle(color: colors.muted, fontSize: 13)),
                ],
              ),
              Text(where, style: TextStyle(color: colors.muted)),
              const SizedBox(height: 8),
              Text(report.topicTaught, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Staff today --------------------------------------------------------------

class _StaffTab extends ConsumerWidget {
  const _StaffTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(staffViewProvider);
    final notifier = ref.read(staffViewProvider.notifier);
    final period = notifier.period;

    return RefreshIndicator(
      key: const Key('staff-today-refresh'),
      onRefresh: notifier.refresh,
      child: ListView(
        key: const Key('staff-today-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _Intro(
            period == DatePeriod.day
                ? context.l10n.staffDeptTodayIntro
                : context.l10n.staffDeptPeriodIntro(period.name),
          ),
          const SizedBox(height: 12),
          PeriodFilter(
            value: period,
            periods: const [DatePeriod.day, DatePeriod.week, DatePeriod.month],
            onChanged: notifier.setPeriod,
          ),
          const SizedBox(height: 16),
          AsyncValueView<StaffView>(
            value: view,
            onRetry: () => ref.invalidate(staffViewProvider),
            data: (context, value) =>
                value.register != null ? _Register(register: value.register!) : _Summary(summary: value.summary!),
          ),
        ],
      ),
    );
  }
}

String _schoolDays(AppLocalizations l10n, Object count) =>
    count == 1 ? l10n.staffOneSchoolDaySoFar : l10n.staffSchoolDaysSoFar('$count');

/// A week or a month: each person's totals, out of the school days so far.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final ReportResult summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    if (summary.rows.isEmpty) {
      return _Empty(
        key: const Key('staff-period-empty'),
        icon: Icons.group_off_outlined,
        title: l10n.staffNobodyInDept,
        body: l10n.staffOfficeAddsStaff,
      );
    }

    Widget figure(Object value, String label, Color colour) => Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colour),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: colors.muted)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _schoolDays(l10n, summary.totals['working_days'] ?? 0),
          key: const Key('staff-period-days'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final row in summary.rows) ...[
          Card(
            key: Key('staff-period-${row['staff_profile_id']}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${row['name']}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('${row['attendance_rate']}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      figure(row['present'] ?? 0, l10n.staffFigPresent, colors.success),
                      figure(row['half_day'] ?? 0, l10n.staffFigHalfDay, colors.info),
                      figure(row['absent'] ?? 0, l10n.staffFigAbsent, colors.danger),
                      figure(row['leave'] ?? 0, l10n.staffFigLeave, colors.info),
                      figure(row['not_marked'] ?? 0, l10n.staffFigUnmarked, colors.muted),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.register});

  final StaffAttendanceRegister register;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (register.holiday != null) {
      return _Empty(
        key: const Key('staff-today-holiday'),
        icon: Icons.event_busy_outlined,
        title: l10n.staffHolidayNamed(register.holiday!.name),
        body: l10n.staffSchoolClosedToday,
      );
    }

    if (register.staff.isEmpty) {
      return _Empty(
        key: const Key('staff-today-empty'),
        icon: Icons.group_off_outlined,
        title: l10n.staffNobodyInDept,
        body: l10n.staffOfficeAddsStaff,
      );
    }

    return _MarkableRegister(date: register.attendanceDate);
  }
}

/// The department's register for the day, marked here (7.1): the web's own
/// register notifier, so the same rules and the same "on leave that day"
/// question. Only for a role that may manage staff attendance - an HOD by
/// default - and read-only otherwise.
class _MarkableRegister extends ConsumerStatefulWidget {
  const _MarkableRegister({required this.date});

  final String date;

  @override
  ConsumerState<_MarkableRegister> createState() => _MarkableRegisterState();
}

class _MarkableRegisterState extends ConsumerState<_MarkableRegister> {
  bool _saving = false;

  StaffAttendanceRegisterParams get _params => StaffAttendanceRegisterParams(date: widget.date);

  Future<void> _save(bool submitted) async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await saveStaffRegister(
      context,
      ref.read(staffAttendanceRegisterProvider(_params).notifier),
      submitted: submitted,
    );
    if (mounted) setState(() => _saving = false);
    if (saved) ref.invalidate(staffViewProvider);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).value;
    final marks = user?.canManage(AppModules.staffAttendance) ?? false;
    final register = ref.watch(staffAttendanceRegisterProvider(_params));
    final notifier = ref.read(staffAttendanceRegisterProvider(_params).notifier);

    return AsyncValueView<StaffAttendanceRegister>(
      value: register,
      onRetry: () => ref.invalidate(staffAttendanceRegisterProvider(_params)),
      data: (context, day) {
        final present = day.staff
            .where((s) => s.status == StaffAttendanceStatus.present || s.status == StaffAttendanceStatus.halfDay)
            .length;
        final unmarked = day.staff.where((s) => s.status == null).length;
        final l10n = context.l10n;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unmarked > 0
                  ? l10n.staffInOfUnmarked(present, day.staff.length, unmarked)
                  : l10n.staffInOf(present, day.staff.length),
              key: const Key('staff-today-summary'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final person in day.staff) ...[
              _StaffRow(
                person: person,
                onMark: marks && !_saving ? (status) => notifier.setStatus(person.staffProfileId, status) : null,
              ),
              const SizedBox(height: 8),
            ],
            if (marks) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  OutlinedButton(
                    key: const Key('staff-register-all-present'),
                    onPressed: _saving ? null : notifier.markAllPresent,
                    child: Text(l10n.staffAllPresent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('staff-register-save'),
                      onPressed: _saving || !notifier.isComplete ? null : () => _save(day.submitted),
                      child: Text(
                        _saving
                            ? l10n.staffSaving
                            : notifier.isComplete
                            ? (day.submitted ? l10n.staffUpdateRegister : l10n.staffSubmitRegister)
                            : l10n.staffMarkEveryone(unmarked),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.person, this.onMark});

  final StaffRosterEntry person;

  /// Null where the register is only read.
  final ValueChanged<StaffAttendanceStatus>? onMark;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final times = [
      if (person.checkIn != null) l10n.staffTimeIn(formatClock(person.checkIn!)),
      if (person.checkOut != null) l10n.staffTimeOut(formatClock(person.checkOut!)),
      if (person.checkedInFromApp) l10n.staffFromTheApp,
    ].join(' · ');

    final mark = onMark;
    final badge = _badge(l10n);
    if (mark != null) {
      return Card(
        key: Key('staff-today-${person.staffProfileId}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (times.isNotEmpty) Text(times, style: TextStyle(color: colors.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in StaffAttendanceStatus.values)
                    ChoiceChip(
                      key: Key('staff-mark-${person.staffProfileId}-${status.apiValue}'),
                      label: Text(staffAttendanceLabel(l10n, status)),
                      selected: person.status == status,
                      onSelected: (_) => mark(status),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      key: Key('staff-today-${person.staffProfileId}'),
      child: ListTile(
        title: Text(person.name),
        subtitle: times.isEmpty ? null : Text(times, style: TextStyle(color: colors.muted)),
        trailing: badge,
      ),
    );
  }

  Widget _badge(AppLocalizations l10n) {
    return switch (person.status) {
      null => StatusBadge(label: l10n.staffNotMarked, tone: BadgeTone.neutral),
      StaffAttendanceStatus.present =>
        person.late
            ? StatusBadge(label: l10n.staffPresentLate, tone: BadgeTone.warning)
            : StatusBadge(label: l10n.staffPresent, tone: BadgeTone.success),
      StaffAttendanceStatus.halfDay => StatusBadge(label: l10n.staffHalfDay, tone: BadgeTone.info),
      StaffAttendanceStatus.leave => StatusBadge(label: l10n.staffNavLeave, tone: BadgeTone.info),
      StaffAttendanceStatus.absent => StatusBadge(label: l10n.staffAbsent, tone: BadgeTone.danger),
    };
  }
}

// -- Leave --------------------------------------------------------------------

/// The department's leave waiting for a decision (7.1). Asked before either
/// way: on a phone a tap meant for the next card is easy, and the person
/// is told at once.
class _LeaveTab extends ConsumerWidget {
  const _LeaveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      key: const Key('department-leave-refresh'),
      onRefresh: () => ref.refresh(leaveToDecideProvider.future),
      child: ListView(
        key: const Key('department-leave-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _Intro(context.l10n.staffDeptLeaveIntro),
          const SizedBox(height: 16),
          AsyncValueView<List<StaffLeave>>(
            value: ref.watch(leaveToDecideProvider),
            onRetry: () => ref.invalidate(leaveToDecideProvider),
            isEmpty: (list) => list.isEmpty,
            emptyBuilder: (context) => _Empty(
              key: const Key('department-leave-empty'),
              icon: Icons.event_available_outlined,
              title: context.l10n.staffNothingToDecide,
              body: context.l10n.staffNothingToDecideBody,
            ),
            data: (context, list) => Column(
              children: [
                for (final leave in list) ...[_LeaveCard(leave: leave), const SizedBox(height: 10)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveCard extends ConsumerStatefulWidget {
  const _LeaveCard({required this.leave});

  final StaffLeave leave;

  @override
  ConsumerState<_LeaveCard> createState() => _LeaveCardState();
}

class _LeaveCardState extends ConsumerState<_LeaveCard> {
  bool _busy = false;

  StaffLeave get leave => widget.leave;

  String _dates(AppLocalizations l10n) {
    final start = formatIsoDate(leave.startDate);
    return leave.startDate == leave.endDate ? start : l10n.staffDateRange(start, formatIsoDate(leave.endDate));
  }

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      title: approve ? l10n.staffApproveLeaveQ : l10n.staffRejectLeaveQ,
      message: l10n.staffLeaveDecideBody(
        leave.staffName ?? l10n.staffThisRequest,
        leaveTypeLabel(l10n, leave.leaveType),
        _dates(l10n),
      ),
      confirmLabel: approve ? l10n.staffApprove : l10n.staffReject,
      isDestructive: !approve,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(staffLeaveRepositoryProvider);
    try {
      var confirm = false;
      while (true) {
        try {
          approve ? await repository.approve(leave.id, confirm: confirm) : await repository.reject(leave.id);
          break;
        } on Failure catch (failure) {
          // Leave for a day the person was at work is asked about first
          // (decided 2026-11-02); the server names the days.
          if (failure.code == 'WORKED_ON_LEAVE_DAY' && !confirm && mounted) {
            confirm = await confirmDialog(
              context,
              title: l10n.staffAtWorkThatDay,
              message: failure.message,
              confirmLabel: l10n.staffApproveAnyway,
            );
            if (confirm) continue;
            return;
          }
          rethrow;
        }
      }
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? l10n.staffLeaveApprovedDone : l10n.staffLeaveRejectedDone)),
      );
      ref.invalidate(leaveToDecideProvider);
    } on Failure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(mounted ? failure.localizedMessage(context) : failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    return Card(
      key: Key('department-leave-${leave.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(leave.staffName ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text('${leaveTypeLabel(l10n, leave.leaveType)} · ${_dates(l10n)}', style: TextStyle(color: colors.muted)),
            const SizedBox(height: 6),
            Text(leave.reason),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('department-leave-reject-${leave.id}'),
                  onPressed: _busy ? null : () => _decide(approve: false),
                  child: Text(l10n.staffReject),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('department-leave-approve-${leave.id}'),
                  onPressed: _busy ? null : () => _decide(approve: true),
                  child: Text(l10n.staffApprove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -- This month ---------------------------------------------------------------

class _MonthTab extends ConsumerWidget {
  const _MonthTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      key: const Key('month-refresh'),
      onRefresh: () => ref.refresh(departmentMonthProvider.future),
      child: ListView(
        key: const Key('month-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _Intro(context.l10n.staffMonthIntro),
          const SizedBox(height: 16),
          AsyncValueView<HodDepartmentReport>(
            value: ref.watch(departmentMonthProvider),
            onRetry: () => ref.invalidate(departmentMonthProvider),
            isEmpty: (report) => report.teachers.isEmpty,
            emptyBuilder: (context) => _Empty(
              key: const Key('month-empty'),
              icon: Icons.group_off_outlined,
              title: context.l10n.staffNoTeachersInDept,
              body: context.l10n.staffOfficeAddsStaff,
            ),
            data: (context, report) => Column(
              children: [
                for (final teacher in report.teachers) ...[_TeacherCard(row: teacher), const SizedBox(height: 10)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.row});

  final HodTeacherRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    Widget figure(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
        ],
      ),
    );

    return Card(
      key: Key('month-${row.staffProfileId}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.teacherName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                row.status == HodTeacherStatus.onTrack
                    ? StatusBadge(label: l10n.staffOnTrack, tone: BadgeTone.success)
                    : StatusBadge(label: l10n.staffNeedsALook, tone: BadgeTone.warning),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                figure('${row.reportsSubmitted}/${row.classesTaught}', l10n.staffFigReportsPeriods),
                figure('${row.reportsPendingReview}', l10n.staffFigToReview),
                figure('${row.syllabusPercent}%', l10n.staffFigSyllabus),
                figure('${row.attendancePercent.round()}%', l10n.staffFigAttendance),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
