import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/module_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../syllabus/data/models/my_syllabus_class.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/my_teaching_providers.dart';
import 'marks_tab.dart';

/// The Teaching tab in the School365ai app (docs/teacher-app.md, T3): the
/// teacher's own reports, and the syllabus of each class they teach. A
/// report is filed from its period on Today, where the period is already
/// known, so this tab has no "new report" button.
class TeachingScreen extends ConsumerWidget {
  const TeachingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    // Only the parts the school uses: a part switched off is left out
    // rather than shown answering "switched off".
    final parts = [
      if (user?.canView(AppModules.teachingReports) ?? false)
        (const Tab(key: Key('teaching-tab-reports'), text: 'Reports'), const _ReportsTab()),
      if (user?.canView(AppModules.syllabus) ?? false)
        (const Tab(key: Key('teaching-tab-syllabus'), text: 'Syllabus'), const _SyllabusTab()),
      if (user?.canView(AppModules.assessments) ?? false)
        (const Tab(key: Key('teaching-tab-marks'), text: 'Marks'), const MarksTab()),
    ];

    if (parts.isEmpty) return const SizedBox.shrink();

    return DefaultTabController(
      length: parts.length,
      child: Column(
        children: [
          TabBar(key: const Key('teaching-tabs'), tabs: [for (final part in parts) part.$1]),
          Expanded(child: TabBarView(children: [for (final part in parts) part.$2])),
        ],
      ),
    );
  }
}

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);
    final colors = context.appColors;

    return RefreshIndicator(
      key: const Key('my-reports-refresh'),
      onRefresh: () => ref.read(myReportsProvider.notifier).refresh(),
      child: ListView(
        key: const Key('my-reports-list'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'What you taught, period by period, and whether it has been reviewed. '
            'File a report from its period on Today.',
            style: TextStyle(color: colors.muted),
          ),
          const SizedBox(height: 16),
          if (!reports.hasValue)
            AsyncValueView<MyReports>(
              value: reports,
              onRetry: () => ref.read(myReportsProvider.notifier).retry(),
              data: (context, value) => const SizedBox.shrink(),
            )
          else if (reports.requireValue.items.isEmpty)
            const _Empty(
              key: Key('my-reports-empty'),
              icon: Icons.description_outlined,
              title: 'No reports yet.',
              body: 'Once a period has begun, tap it on Today to say what was taught.',
            )
          else ...[
            for (final report in reports.requireValue.items) ...[
              _ReportCard(report: report),
              const SizedBox(height: 10),
            ],
            if (reports.requireValue.hasMore)
              Center(
                child: TextButton(
                  key: const Key('my-reports-more'),
                  onPressed: () => ref.read(myReportsProvider.notifier).loadMore(),
                  child: const Text('Show older reports'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final where = [
      report.classSectionName,
      if (report.periodNumber != null) 'Period ${report.periodNumber}',
    ].whereType<String>().join(' · ');

    return Card(
      key: Key('my-report-${report.id}'),
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
                      report.subjectName ?? 'Report',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ReviewBadge(report: report),
                ],
              ),
              const SizedBox(height: 2),
              Text('${formatIsoDate(report.reportDate)} · $where', style: TextStyle(color: colors.muted)),
              const SizedBox(height: 8),
              Text(report.topicTaught, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reviewed by the HOD, or still waiting for them.
class ReviewBadge extends StatelessWidget {
  const ReviewBadge({super.key, required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context) => report.isReviewed
      ? const StatusBadge(label: 'Reviewed', tone: BadgeTone.success)
      : const StatusBadge(label: 'Awaiting review', tone: BadgeTone.neutral);
}

class _SyllabusTab extends ConsumerWidget {
  const _SyllabusTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(mySyllabusProvider);
    final colors = context.appColors;

    return RefreshIndicator(
      key: const Key('my-syllabus-refresh'),
      onRefresh: () => ref.refresh(mySyllabusProvider.future),
      child: ListView(
        key: const Key('my-syllabus-list'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Each class and subject you teach this year. Tap one to tick off topics.',
            style: TextStyle(color: colors.muted),
          ),
          const SizedBox(height: 16),
          AsyncValueView<List<MySyllabusClass>>(
            value: classes,
            onRetry: () => ref.invalidate(mySyllabusProvider),
            isEmpty: (rows) => rows.isEmpty,
            emptyBuilder: (context) => const _Empty(
              key: Key('my-syllabus-empty'),
              icon: Icons.menu_book_outlined,
              title: 'No classes on your timetable this year.',
              body: 'Your school office puts you on the timetable; your classes appear here once it does.',
            ),
            data: (context, rows) => Column(
              children: [
                for (final row in rows) ...[_SyllabusCard(row: row), const SizedBox(height: 10)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyllabusCard extends StatelessWidget {
  const _SyllabusCard({required this.row});

  final MySyllabusClass row;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final noOutline = row.totalTopics == 0;

    return Card(
      key: Key('my-syllabus-${row.classSectionId}-${row.subjectId}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          Uri(
            path: '/teaching/syllabus/${row.classSectionId}/${row.subjectId}',
            queryParameters: {'label': '${row.subjectName} · ${row.classSection}'},
          ).toString(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.subjectName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    noOutline ? 'No topics yet' : '${row.completedTopics} of ${row.totalTopics}',
                    style: TextStyle(color: colors.muted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Text(row.classSection, style: TextStyle(color: colors.muted)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: noOutline ? 0 : row.completedTopics / row.totalTopics,
                  minHeight: 8,
                  backgroundColor: colors.muted.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
