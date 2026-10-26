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

/// The Department tab, for an HOD (docs/teacher-app.md, T7): the reports
/// waiting for their review, who in the department is in today, and how
/// each teacher's month is going. The register itself is marked on the
/// website; here it is read.
class DepartmentScreen extends StatelessWidget {
  const DepartmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            key: Key('department-tabs'),
            tabs: [
              Tab(key: Key('department-tab-review'), text: 'To review'),
              Tab(key: Key('department-tab-staff'), text: 'Staff today'),
              Tab(key: Key('department-tab-month'), text: 'This month'),
            ],
          ),
          Expanded(child: TabBarView(children: [_ReviewTab(), _StaffTab(), _MonthTab()])),
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

    return RefreshIndicator(
      key: const Key('review-refresh'),
      onRefresh: () => ref.read(reviewQueueProvider.notifier).refresh(),
      child: ListView(
        key: const Key('review-list'),
        padding: const EdgeInsets.all(16),
        children: [
          const _Intro('Reports from your department that nobody has reviewed yet. Open one to read and review it.'),
          const SizedBox(height: 16),
          if (!queue.hasValue)
            AsyncValueView<ReviewQueue>(
              value: queue,
              onRetry: () => ref.read(reviewQueueProvider.notifier).retry(),
              data: (context, value) => const SizedBox.shrink(),
            )
          else if (queue.requireValue.items.isEmpty)
            const _Empty(
              key: Key('review-empty'),
              icon: Icons.task_alt,
              title: 'Nothing waiting for review.',
              body: 'Reports your department files appear here until you review them.',
            )
          else ...[
            for (final report in queue.requireValue.items) ...[_ReviewCard(report: report), const SizedBox(height: 10)],
            if (queue.requireValue.hasMore)
              Center(
                child: TextButton(
                  key: const Key('review-more'),
                  onPressed: () => ref.read(reviewQueueProvider.notifier).loadMore(),
                  child: const Text('Show more'),
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
      if (report.periodNumber != null) 'Period ${report.periodNumber}',
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
                      report.teacherName ?? 'A teacher',
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
    return RefreshIndicator(
      key: const Key('staff-today-refresh'),
      onRefresh: () => ref.refresh(staffTodayProvider.future),
      child: ListView(
        key: const Key('staff-today-list'),
        padding: const EdgeInsets.all(16),
        children: [
          const _Intro(
            'Your department today: who is in, and when they arrived. The register is marked on the website.',
          ),
          const SizedBox(height: 16),
          AsyncValueView<StaffAttendanceRegister>(
            value: ref.watch(staffTodayProvider),
            onRetry: () => ref.invalidate(staffTodayProvider),
            data: (context, register) => _Register(register: register),
          ),
        ],
      ),
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.register});

  final StaffAttendanceRegister register;

  @override
  Widget build(BuildContext context) {
    if (register.holiday != null) {
      return _Empty(
        key: const Key('staff-today-holiday'),
        icon: Icons.event_busy_outlined,
        title: 'Holiday: ${register.holiday!.name}',
        body: 'The school is closed today.',
      );
    }

    if (register.staff.isEmpty) {
      return const _Empty(
        key: Key('staff-today-empty'),
        icon: Icons.group_off_outlined,
        title: 'Nobody in your department yet.',
        body: 'The school office adds staff to departments on the website.',
      );
    }

    final present = register.staff
        .where((s) => s.status == StaffAttendanceStatus.present || s.status == StaffAttendanceStatus.halfDay)
        .length;
    final unmarked = register.staff.where((s) => s.status == null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$present of ${register.staff.length} in${unmarked > 0 ? ' · $unmarked not marked yet' : ''}',
          key: const Key('staff-today-summary'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final person in register.staff) ...[_StaffRow(person: person), const SizedBox(height: 8)],
      ],
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.person});

  final StaffRosterEntry person;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final times = [
      if (person.checkIn != null) 'In ${formatClock(person.checkIn!)}',
      if (person.checkOut != null) 'out ${formatClock(person.checkOut!)}',
      if (person.checkedInFromApp) 'from the app',
    ].join(' · ');

    return Card(
      key: Key('staff-today-${person.staffProfileId}'),
      child: ListTile(
        title: Text(person.name),
        subtitle: times.isEmpty ? null : Text(times, style: TextStyle(color: colors.muted)),
        trailing: switch (person.status) {
          null => const StatusBadge(label: 'Not marked', tone: BadgeTone.neutral),
          StaffAttendanceStatus.present =>
            person.late
                ? const StatusBadge(label: 'Present · late', tone: BadgeTone.warning)
                : const StatusBadge(label: 'Present', tone: BadgeTone.success),
          StaffAttendanceStatus.halfDay => const StatusBadge(label: 'Half day', tone: BadgeTone.info),
          StaffAttendanceStatus.leave => const StatusBadge(label: 'Leave', tone: BadgeTone.info),
          StaffAttendanceStatus.absent => const StatusBadge(label: 'Absent', tone: BadgeTone.danger),
        },
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
          const _Intro('Each teacher this month: reports filed against periods taught, syllabus covered, attendance.'),
          const SizedBox(height: 16),
          AsyncValueView<HodDepartmentReport>(
            value: ref.watch(departmentMonthProvider),
            onRetry: () => ref.invalidate(departmentMonthProvider),
            isEmpty: (report) => report.teachers.isEmpty,
            emptyBuilder: (context) => const _Empty(
              key: Key('month-empty'),
              icon: Icons.group_off_outlined,
              title: 'No teachers in your department yet.',
              body: 'The school office adds staff to departments on the website.',
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
                    ? const StatusBadge(label: 'On track', tone: BadgeTone.success)
                    : const StatusBadge(label: 'Needs a look', tone: BadgeTone.warning),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                figure('${row.reportsSubmitted}/${row.classesTaught}', 'reports / periods'),
                figure('${row.reportsPendingReview}', 'to review'),
                figure('${row.syllabusPercent}%', 'syllabus'),
                figure('${row.attendancePercent.round()}%', 'attendance'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
