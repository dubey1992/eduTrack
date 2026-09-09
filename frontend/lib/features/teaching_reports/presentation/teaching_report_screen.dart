import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../timetable/application/timetable_grid_notifier.dart';
import '../../timetable/data/models/day_of_week.dart';
import '../../timetable/data/models/timetable_entry.dart';
import '../application/teaching_report_list_notifier.dart';
import '../application/teaching_report_summary_notifier.dart';
import '../data/models/teaching_report.dart';
import '../data/models/teaching_report_summary.dart';
import 'widgets/submit_report_dialog.dart';

/// Phase 11 - "My Teaching Today" (a Teacher/HOD's own scheduled periods for
/// today, cross-referenced against what they've already filed - see
/// TimetableGridParams.forTeacher and TeachingReportListParams) plus
/// "Reports to Review" (an HOD/SchoolAdmin/SuperAdmin's server-scoped feed
/// of everyone else's reports, same single-list-scoped-server-side
/// convention as Staff Leave - self-review is blocked server-side, not by
/// hiding the ability here).
class TeachingReportScreen extends ConsumerStatefulWidget {
  const TeachingReportScreen({super.key});

  @override
  ConsumerState<TeachingReportScreen> createState() => _TeachingReportScreenState();
}

class _TeachingReportScreenState extends ConsumerState<TeachingReportScreen> {
  int? _schoolFilter;

  static const _submitterRoles = {UserRole.teacher, UserRole.hod};
  static const _reviewerRoles = {UserRole.hod, UserRole.schoolAdmin, UserRole.superAdmin};

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final canSubmit = _submitterRoles.contains(actor.role);
    final canReview = _reviewerRoles.contains(actor.role);

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
              Text('Daily Teaching Reports', style: Theme.of(context).textTheme.headlineSmall),
              SchoolFilterDropdown(
                selected: _schoolFilter,
                onChanged: (schoolId) {
                  setState(() => _schoolFilter = schoolId);
                  ref.read(teachingReportSummaryNotifierProvider.notifier).setSchoolFilter(schoolId);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Track today\'s scheduled periods and their teaching reports.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const _SummaryRow(),
          if (canSubmit) ...[
            const SizedBox(height: 24),
            Text('My Teaching Today', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _MyScheduleToday(teacherId: actor.id, reportDate: _today),
          ],
          if (canReview) ...[
            const SizedBox(height: 24),
            Text('Reports to Review', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ReportsToReview(schoolId: _schoolFilter, actorId: actor.id),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends ConsumerWidget {
  const _SummaryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(teachingReportSummaryNotifierProvider);

    return AsyncValueView<TeachingReportSummary>(
      value: summaryState,
      data: (context, summary) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KpiCard(label: 'Scheduled Today', value: '${summary.scheduled}'),
            KpiCard(label: 'Submitted Today', value: '${summary.submitted}'),
            KpiCard(label: 'Pending Today', value: '${summary.pending}'),
            if (summary.holiday != null)
              Chip(
                avatar: Icon(Icons.beach_access_outlined, size: 18, color: context.appColors.onDangerContainer),
                label: Text('Holiday: ${summary.holiday}'),
                backgroundColor: context.appColors.dangerContainer,
                labelStyle: TextStyle(color: context.appColors.onDangerContainer),
              ),
          ],
        );
      },
    );
  }
}

class _MyScheduleToday extends ConsumerWidget {
  const _MyScheduleToday({required this.teacherId, required this.reportDate});

  final int teacherId;
  final String reportDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holiday = ref.watch(teachingReportSummaryNotifierProvider).value?.holiday;
    if (holiday != null) {
      return Card(
        child: Padding(padding: const EdgeInsets.all(20), child: Text('No periods today - $holiday is a holiday.')),
      );
    }

    final today = _todayDayOfWeek();
    if (today == null) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(20), child: Text('No periods are scheduled today.')),
      );
    }

    final scheduleParams = TimetableGridParams.forTeacher(teacherId);
    final reportParams = TeachingReportListParams(teacherId: teacherId, reportDate: reportDate);
    final entriesState = ref.watch(timetableGridProvider(scheduleParams));
    final reportsState = ref.watch(teachingReportListNotifierProvider(reportParams));

    return AsyncValueView<List<TimetableEntry>>(
      value: entriesState,
      onRetry: () => ref.invalidate(timetableGridProvider(scheduleParams)),
      data: (context, entries) {
        final todaysEntries = entries.where((e) => e.dayOfWeek == today).toList()
          ..sort((a, b) => (a.periodNumber ?? 0).compareTo(b.periodNumber ?? 0));

        if (todaysEntries.isEmpty) {
          return const Card(
            child: Padding(padding: EdgeInsets.all(20), child: Text('No periods are scheduled for you today.')),
          );
        }

        return AsyncValueView<PagedList<TeachingReport>>(
          value: reportsState,
          onRetry: () => ref.invalidate(teachingReportListNotifierProvider(reportParams)),
          data: (context, page) {
            final filedByEntry = {for (final report in page.items) report.timetableEntryId: report};

            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(8),
                itemCount: todaysEntries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = todaysEntries[index];
                  final report = filedByEntry[entry.id];

                  return ListTile(
                    title: Text('Period ${entry.periodNumber ?? '-'} · ${entry.subjectName ?? ''}'),
                    subtitle: Text(entry.classSectionName ?? ''),
                    trailing: report == null
                        ? FilledButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => SubmitReportDialog(entry: entry, reportDate: reportDate),
                            ),
                            child: const Text('Submit Report'),
                          )
                        : StatusBadge(
                            label: report.isReviewed ? 'Reviewed' : 'Submitted',
                            tone: report.isReviewed ? BadgeTone.success : BadgeTone.info,
                          ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  DayOfWeek? _todayDayOfWeek() {
    final name = DateFormat('EEEE').format(DateTime.now()).toLowerCase();
    for (final day in DayOfWeek.values) {
      if (day.apiValue == name) return day;
    }
    return null;
  }
}

Future<void> _review(
  BuildContext context,
  WidgetRef ref,
  TeachingReportListParams params,
  TeachingReport report,
) async {
  try {
    await ref.read(teachingReportListNotifierProvider(params).notifier).review(report);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report reviewed.')));
    }
  } catch (error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _ReportsToReview extends ConsumerStatefulWidget {
  const _ReportsToReview({required this.schoolId, required this.actorId});

  final int? schoolId;
  final int actorId;

  @override
  ConsumerState<_ReportsToReview> createState() => _ReportsToReviewState();
}

class _ReportsToReviewState extends ConsumerState<_ReportsToReview> {
  @override
  Widget build(BuildContext context) {
    final params = TeachingReportListParams(schoolId: widget.schoolId);
    final reportsState = ref.watch(teachingReportListNotifierProvider(params));

    return AsyncValueView<PagedList<TeachingReport>>(
      value: reportsState,
      onRetry: () => ref.invalidate(teachingReportListNotifierProvider(params)),
      isEmpty: (page) => page.items.isEmpty,
      emptyBuilder: (context) => const Card(
        child: Padding(padding: EdgeInsets.all(20), child: Text('No teaching reports found.')),
      ),
      data: (context, page) {
        return Column(
          children: [
            ResponsiveBuilder(
              mobile: (context) => _ReportListMobile(reports: page.items, params: params, actorId: widget.actorId),
              desktop: (context) => _ReportListDesktop(reports: page.items, params: params, actorId: widget.actorId),
            ),
            PaginationControls(
              currentPage: page.currentPage,
              lastPage: page.lastPage,
              total: page.total,
              perPage: page.perPage,
              onPageChanged: (p) => ref.read(teachingReportListNotifierProvider(params).notifier).goToPage(p),
              onPerPageChanged: (p) => ref.read(teachingReportListNotifierProvider(params).notifier).setPerPage(p),
            ),
          ],
        );
      },
    );
  }
}

class _ReviewStatusBadge extends StatelessWidget {
  const _ReviewStatusBadge({required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: report.isReviewed ? 'Reviewed' : 'Pending Review',
      tone: report.isReviewed ? BadgeTone.success : BadgeTone.warning,
    );
  }
}

class _ReportListMobile extends ConsumerWidget {
  const _ReportListMobile({required this.reports, required this.params, required this.actorId});

  final List<TeachingReport> reports;
  final TeachingReportListParams params;
  final int actorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: reports.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final report = reports[index];
        final canReviewThis = !report.isReviewed && report.teacherId != actorId;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.teacherName ?? 'Teacher #${report.teacherId}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _ReviewStatusBadge(report: report),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${report.subjectName ?? ''} · ${report.classSectionName ?? ''} · ${report.reportDate}'),
                const SizedBox(height: 4),
                Text(report.topicTaught),
                if (canReviewThis) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => _review(context, ref, params, report),
                      child: const Text('Mark Reviewed'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReportListDesktop extends ConsumerWidget {
  const _ReportListDesktop({required this.reports, required this.params, required this.actorId});

  final List<TeachingReport> reports;
  final TeachingReportListParams params;
  final int actorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Teacher')),
            DataColumn(label: Text('Class/Section')),
            DataColumn(label: Text('Subject')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Topic Taught')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Action')),
          ],
          rows: [
            for (final report in reports)
              DataRow(
                cells: [
                  DataCell(Text(report.teacherName ?? 'Teacher #${report.teacherId}')),
                  DataCell(Text(report.classSectionName ?? '—')),
                  DataCell(Text(report.subjectName ?? '—')),
                  DataCell(Text(report.reportDate)),
                  DataCell(SizedBox(width: 220, child: Text(report.topicTaught, overflow: TextOverflow.ellipsis))),
                  DataCell(_ReviewStatusBadge(report: report)),
                  DataCell(
                    (!report.isReviewed && report.teacherId != actorId)
                        ? TextButton(
                            onPressed: () => _review(context, ref, params, report),
                            child: const Text('Mark Reviewed'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
