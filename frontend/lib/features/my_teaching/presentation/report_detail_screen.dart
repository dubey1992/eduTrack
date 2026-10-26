import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../auth/application/auth_notifier.dart';
import '../../my_department/application/department_providers.dart';
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

class _Report extends ConsumerWidget {
  const _Report({required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An HOD reading a colleague's report needs to know whose it is; the
    // author does not need telling.
    final byAnother = ref.watch(authNotifierProvider).value?.id != report.teacherId;
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
        if (byAnother && report.teacherName != null)
          Text(
            'By ${report.teacherName}',
            key: const Key('report-author'),
            style: TextStyle(color: colors.muted),
          ),
        const SizedBox(height: 20),
        field('What was taught', report.topicTaught),
        field('Syllabus topic ticked off', report.syllabusTopicName),
        field('Homework', report.homework),
        field('Remarks', report.remarks),
        _ReviewAction(report: report),
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

/// "Mark reviewed", for an HOD reading a colleague's report that nobody has
/// reviewed yet (docs/teacher-app.md, T7). Never on the HOD's own report:
/// nobody reviews their own, and the server refuses it too.
class _ReviewAction extends ConsumerStatefulWidget {
  const _ReviewAction({required this.report});

  final TeachingReport report;

  @override
  ConsumerState<_ReviewAction> createState() => _ReviewActionState();
}

class _ReviewActionState extends ConsumerState<_ReviewAction> {
  bool _busy = false;
  String? _problem;

  Future<void> _review() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref.read(reviewReportProvider).call(widget.report.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report reviewed.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (!mounted) return;
      setState(
        () => _problem = switch (failure.code) {
          'TEACHING_REPORT_ALREADY_REVIEWED' => 'Somebody has already reviewed this report.',
          'FORBIDDEN' => 'This report is not from your department, so it is not yours to review.',
          'NETWORK_ERROR' => 'No connection. It was not reviewed - try again when you have signal.',
          _ => failure.message,
        },
      );
      if (failure.code == 'TEACHING_REPORT_ALREADY_REVIEWED') ref.invalidate(myReportProvider(widget.report.id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authNotifierProvider).value;
    final report = widget.report;
    final mayReview = me?.role == UserRole.hod && !report.isReviewed && report.teacherId != me?.id;
    if (!mayReview) return const SizedBox.shrink();

    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_problem != null) ...[
            Text(
              _problem!,
              key: const Key('report-review-problem'),
              style: TextStyle(color: colors.danger),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('report-review'),
              onPressed: _busy ? null : _review,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.done_all),
              label: const Text('Mark reviewed'),
            ),
          ),
        ],
      ),
    );
  }
}
