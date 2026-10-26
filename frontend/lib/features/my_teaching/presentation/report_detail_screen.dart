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
import 'file_report_screen.dart';
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
        if (report.reviewNote != null && report.reviewNote!.isNotEmpty) ...[
          HodNote(report: report),
          const SizedBox(height: 16),
        ],
        _ChangeAction(report: report),
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

  Future<void> _sendBack() async {
    if (_busy) return;
    final note = await showDialog<String>(context: context, builder: (context) => const _SendBackDialog());
    if (note == null || !mounted) return;

    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref.read(sendBackReportProvider).call(widget.report.id, note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent back to the teacher.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (!mounted) return;
      setState(
        () => _problem = switch (failure.code) {
          'TEACHING_REPORT_ALREADY_REVIEWED' => 'Somebody has already reviewed this report.',
          'TEACHING_REPORT_RETURNED' => 'This report is already back with its teacher.',
          'FORBIDDEN' => 'This report is not from your department, so it is not yours to send back.',
          'NETWORK_ERROR' => 'No connection. It was not sent back - try again when you have signal.',
          _ => failure.message,
        },
      );
      ref.invalidate(myReportProvider(widget.report.id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
          if (report.isReturned) ...[
            Text(
              'Sent back to ${report.teacherName ?? 'the teacher'}. It comes back to your list when they send it '
              'again - or mark it reviewed now if it was fine after all.',
              key: const Key('report-returned-waiting'),
              style: TextStyle(color: colors.muted),
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
          if (!report.isReturned) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                key: const Key('report-send-back'),
                onPressed: _busy ? null : _sendBack,
                icon: const Icon(Icons.undo),
                label: const Text('Send back with a note'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The HOD's note on a report - why it was sent back, or a word with the
/// review (docs/teacher-app.md, T7).
class HodNote extends StatelessWidget {
  const HodNote({super.key, required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final who = report.isReturned ? report.returnedByName : report.reviewedByName;
    final returned = report.isReturned;

    return Container(
      key: const Key('report-hod-note'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: returned ? colors.warningContainer : colors.infoContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            returned ? 'Sent back by ${who ?? 'your HOD'}' : 'Note from ${who ?? 'your HOD'}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: returned ? colors.onWarningContainer : colors.onInfoContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report.reviewNote ?? '',
            style: TextStyle(height: 1.35, color: returned ? colors.onWarningContainer : colors.onInfoContainer),
          ),
        ],
      ),
    );
  }
}

/// "Change and send again", for the author of a report sent back to them.
class _ChangeAction extends ConsumerWidget {
  const _ChangeAction({required this.report});

  final TeachingReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(authNotifierProvider).value?.id == report.teacherId;
    if (!mine || !report.isReturned) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 48,
        child: FilledButton.icon(
          key: const Key('report-change'),
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<bool>(builder: (context) => FileReportScreen.change(changing: report))),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Change and send again'),
        ),
      ),
    );
  }
}

/// What should change, before a report goes back. A note is required: the
/// teacher has to know what to do.
class _SendBackDialog extends StatefulWidget {
  const _SendBackDialog();

  @override
  State<_SendBackDialog> createState() => _SendBackDialogState();
}

class _SendBackDialogState extends State<_SendBackDialog> {
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _send() {
    final note = _note.text.trim();
    if (note.isEmpty) {
      setState(() => _error = 'Say what should change.');
      return;
    }
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('send-back-dialog'),
      title: const Text('Send back to the teacher?'),
      content: TextField(
        key: const Key('send-back-note'),
        controller: _note,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'What should change',
          hintText: 'e.g. Please add what the class practised.',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const Key('send-back-confirm'), onPressed: _send, child: const Text('Send back')),
      ],
    );
  }
}
