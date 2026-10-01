import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../application/student_performance_notifier.dart';
import '../data/models/student.dart';
import '../data/student_repository.dart';
import '../data/models/student_performance.dart';

/// What one student's marks add up to (docs/assessments.md).
///
/// A term at a time, with the previous one beside it and the register for
/// the same period underneath, because "why is this subject weak" is very
/// often answered by how many days the child was there.
///
/// Nothing on this page is invented: a subject with no mark, a term with
/// nothing before it and a period with no working day all read as a dash.
class StudentPerformanceDialog extends ConsumerStatefulWidget {
  const StudentPerformanceDialog({super.key, required this.student});

  final Student student;

  @override
  ConsumerState<StudentPerformanceDialog> createState() => _StudentPerformanceDialogState();
}

class _StudentPerformanceDialogState extends ConsumerState<StudentPerformanceDialog> {
  bool _downloading = false;
  bool _sending = false;

  Student get student => widget.student;

  /// The same figures as a page to print or send home.
  ///
  /// Only offered once there is something to print: a button that produces
  /// a sheet saying "nothing published yet" wastes somebody's paper.
  Future<void> _download(StudentPerformance performance) async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await ref
          .read(studentRepositoryProvider)
          .progressReport(student.id, academicTermId: performance.term?.id);

      saveBytes(fileName: 'progress-report-${student.admissionNumber}.pdf', bytes: bytes, mimeType: 'application/pdf');

      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Progress report downloaded.')));
    } catch (error) {
      final message = error is Failure ? error.message : error.toString().replaceFirst('UnsupportedError: ', '');
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Emails the report to the guardian, when staff ask for it.
  ///
  /// Never on a schedule: this is a document about a child, and somebody
  /// should have looked at it first (docs/insights.md).
  Future<void> _send(StudentPerformance performance) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Send to the guardian?',
      message:
          "The progress report for ${student.name} will be emailed to their guardian. "
          'They will see every figure on this page.',
      confirmLabel: 'Send',
    );

    if (!confirmed || !mounted) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(studentRepositoryProvider).sendProgressReport(student.id, academicTermId: performance.term?.id);

      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Progress report sent to the guardian.')));
    } catch (error) {
      final message = error is Failure ? error.message : error.toString();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentPerformanceProvider(student.id));
    final performance = state.value;

    return AlertDialog(
      title: Text('Performance · ${student.name}'),
      content: ConstrainedBox(
        // Bounded so the spinner does not stretch the dialog to the whole
        // viewport before the figures arrive.
        constraints: const BoxConstraints(minWidth: 720, maxWidth: 820, maxHeight: 560),
        child: AsyncValueView<StudentPerformance>(
          value: state,
          onRetry: () => ref.read(studentPerformanceProvider(student.id).notifier).refresh(),
          data: (context, performance) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TermBar(studentId: student.id, performance: performance),
                const SizedBox(height: 16),
                if (performance.term == null)
                  const Text('This school has no terms yet, so there is nothing to report on.')
                else if (!performance.hasMarks)
                  Text(
                    'No published result in ${performance.term!.name} yet. '
                    'Marks appear here once a test has been published.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  )
                else ...[
                  _Summary(performance: performance),
                  const SizedBox(height: 16),
                  _SubjectTable(performance: performance),
                  if (performance.hasTopics) ...[const SizedBox(height: 20), _Topics(performance: performance)],
                  if (performance.insights.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _Insights(insights: performance.insights),
                  ],
                  if (performance.recommendations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _Recommendations(recommendations: performance.recommendations),
                  ],
                ],
                const SizedBox(height: 20),
                _Attendance(performance: performance),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (performance != null && performance.hasMarks)
          TextButton.icon(
            onPressed: _sending || _downloading ? null : () => _send(performance),
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.mail_outlined, size: 18),
            label: const Text('Send to guardian'),
          ),
        if (performance != null && performance.hasMarks)
          OutlinedButton.icon(
            onPressed: _downloading || _sending ? null : () => _download(performance),
            icon: _downloading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Download PDF'),
          ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

class _TermBar extends ConsumerWidget {
  const _TermBar({required this.studentId, required this.performance});

  final int studentId;
  final StudentPerformance performance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (performance.terms.isNotEmpty)
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int>(
              key: const Key('performance-term'),
              initialValue: performance.term?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Term', isDense: true),
              items: [for (final term in performance.terms) DropdownMenuItem(value: term.id, child: Text(term.name))],
              onChanged: (termId) => ref.read(studentPerformanceProvider(studentId).notifier).setTerm(termId),
            ),
          ),
        if (performance.classSectionName != null) Text(performance.classSectionName!, style: muted),
        if (performance.previousTerm != null)
          Text('Compared with ${performance.previousTerm!.name}', style: muted)
        else
          Text('Nothing before this term to compare with', style: muted),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.performance});

  final StudentPerformance performance;

  @override
  Widget build(BuildContext context) {
    final overall = performance.overall;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Figure(label: 'Average', value: _percent(overall.averagePercentage)),
        _Figure(label: 'Class average', value: _percent(overall.classAveragePercentage)),
        _Figure(label: 'Previous term', value: _percent(overall.previousAveragePercentage)),
        _Figure(label: 'Subjects', value: '${overall.subjects}'),
        _Figure(label: 'Tests', value: '${overall.assessments}'),
        if (overall.absent > 0) _Figure(label: 'Missed', value: '${overall.absent}'),
      ],
    );
  }
}

String _percent(String? value) => value == null ? '-' : '$value%';

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SubjectTable extends StatelessWidget {
  const _SubjectTable({required this.performance});

  final StudentPerformance performance;

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Subject')),
          DataColumn(label: Text('Average')),
          DataColumn(label: Text('Grade')),
          DataColumn(label: Text('Class')),
          DataColumn(label: Text('Previous')),
          DataColumn(label: Text('Change')),
          DataColumn(label: Text('Tests')),
        ],
        rows: [
          for (final subject in performance.subjects)
            DataRow(
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(subject.subjectName),
                      if (subject.isWeak(performance.weakBelowPercentage)) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Below the school\'s ${performance.weakBelowPercentage?.round()}% mark',
                          child: Icon(Icons.flag_outlined, size: 16, color: context.appColors.warning),
                        ),
                      ],
                    ],
                  ),
                ),
                DataCell(Text(_percent(subject.averagePercentage))),
                DataCell(Text(subject.grade ?? '-')),
                DataCell(Text(_percent(subject.classAveragePercentage))),
                DataCell(Text(_percent(subject.previousAveragePercentage))),
                DataCell(_Change(subject: subject)),
                DataCell(
                  Text(
                    subject.absent > 0 ? '${subject.assessments} (${subject.absent} missed)' : '${subject.assessments}',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Points gained or lost, with the sign that says which.
class _Change extends StatelessWidget {
  const _Change({required this.subject});

  final SubjectPerformance subject;

  @override
  Widget build(BuildContext context) {
    final value = subject.changeValue;

    if (value == null) return const Text('-');

    final colors = context.appColors;
    final rising = value > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          rising ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: rising ? colors.success : colors.danger,
        ),
        const SizedBox(width: 4),
        Text(value.abs().toStringAsFixed(2), style: TextStyle(color: rising ? colors.success : colors.danger)),
      ],
    );
  }
}

/// Which parts of a subject are weak (docs/insights.md).
///
/// A subject average says Mathematics is at 52%, which a teacher can check
/// and not much else. The chapters the tests named say it is the
/// trigonometry half, which is a lesson they can plan.
///
/// Only subjects whose tests named a topic appear. A school that leaves the
/// field empty sees nothing here rather than a table of dashes.
class _Topics extends StatelessWidget {
  const _Topics({required this.performance});

  final StudentPerformance performance;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Inside each subject', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final subject in performance.subjects.where((subject) => subject.topics.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.subjectName, style: muted),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final topic in subject.topics)
                      _TopicPill(topic: topic, weakBelow: performance.weakBelowPercentage),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({required this.topic, required this.weakBelow});

  final TopicPerformance topic;
  final num? weakBelow;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final weak = topic.isWeak(weakBelow);
    final scheme = Theme.of(context).colorScheme;

    // A topic the student missed entirely has no average - and is not weak,
    // because nobody has measured it.
    final value = topic.averagePercentage == null ? 'not sat' : '${topic.averagePercentage}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: weak ? colors.warning : Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (weak) ...[Icon(Icons.flag_outlined, size: 14, color: colors.warning), const SizedBox(width: 6)],
          Text(topic.topicName),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: weak ? colors.warning : scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// What the rules made of the figures above.
///
/// Sentences rather than scores, each one drawn from numbers the page is
/// already showing - so a teacher can check every claim without leaving the
/// dialog (docs/assessments.md).
class _Insights extends StatelessWidget {
  const _Insights({required this.insights});

  final List<PerformanceInsight> insights;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What this looks like', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final insight in insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  insight.isConcerning ? Icons.error_outline : Icons.trending_up,
                  size: 16,
                  color: insight.isConcerning ? colors.warning : colors.success,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(insight.message)),
              ],
            ),
          ),
      ],
    );
  }
}

/// One next step per finding (docs/insights.md).
///
/// Separate from "What this looks like" because they answer different
/// questions: that section says what the numbers are, this one says what
/// somebody could do. Each carries the figures it came from, so a teacher
/// can disagree with it on the evidence rather than on authority.
class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.recommendations});

  final List<PerformanceInsight> recommendations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What to do next', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final step in recommendations)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(step.message)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Attendance extends StatelessWidget {
  const _Attendance({required this.performance});

  final StudentPerformance performance;

  @override
  Widget build(BuildContext context) {
    final attendance = performance.attendance;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attendance this term', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (attendance.workingDays == 0)
          Text('No school days in this period yet.', style: muted)
        else if (!attendance.wasTaken)
          // The same sentence the progress report prints, so the screen and
          // the page a family is handed cannot say different things.
          Text(
            'The register was not taken in this period '
            '(${attendance.workingDays} school days).',
            style: muted,
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Figure(
                label: 'Attendance',
                value: attendance.attendanceRate == null ? '-' : '${attendance.attendanceRate}%',
              ),
              _Figure(label: 'Present', value: '${attendance.present}'),
              _Figure(label: 'Absent', value: '${attendance.absent}'),
              _Figure(label: 'Leave', value: '${attendance.leave}'),
              _Figure(label: 'School days', value: '${attendance.workingDays}'),
              if (attendance.notMarked > 0) _Figure(label: 'Not marked', value: '${attendance.notMarked}'),
            ],
          ),
      ],
    );
  }
}
