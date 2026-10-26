import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../application/my_teaching_providers.dart';
import 'teaching_screen.dart';

/// One filed report, read-only (docs/teacher-app.md, T3). Opened from its
/// period on Today or from the Reports list. There is no editing: the web
/// has none either, and a report an HOD has reviewed must stay what they
/// reviewed.
class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({super.key, required this.reportId});

  final int reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teaching report')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AsyncValueView<TeachingReport>(
              value: ref.watch(myReportProvider(reportId)),
              onRetry: () => ref.invalidate(myReportProvider(reportId)),
              data: (context, report) => _Report(report: report),
            ),
          ),
        ),
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final where = [
      report.classSectionName,
      if (report.periodNumber != null) 'Period ${report.periodNumber}',
    ].whereType<String>().join(' · ');
    final reviewedOn = report.reviewedAt == null || report.reviewedAt!.length < 10
        ? ''
        : ' on ${formatIsoDate(report.reviewedAt!.substring(0, 10))}';

    Widget field(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: colors.muted, fontSize: 13)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, height: 1.35)),
              ],
            ),
          );

    return ListView(
      key: const Key('report-detail'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                report.subjectName ?? 'Report',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ReviewBadge(report: report),
          ],
        ),
        Text('${formatIsoDate(report.reportDate)} · $where', style: TextStyle(color: colors.muted)),
        const SizedBox(height: 20),
        field('What was taught', report.topicTaught),
        field('Syllabus topic ticked off', report.syllabusTopicName),
        field('Homework', report.homework),
        field('Remarks', report.remarks),
        if (report.isReviewed)
          Text(
            'Reviewed by ${report.reviewedByName ?? 'your HOD'}$reviewedOn.',
            key: const Key('report-reviewed-by'),
            style: TextStyle(color: colors.muted),
          ),
      ],
    );
  }
}
