import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../application/student_performance_notifier.dart';
import '../data/models/student.dart';
import '../data/models/student_performance.dart';

/// What one student's marks add up to (docs/assessments.md).
///
/// A term at a time, with the previous one beside it and the register for
/// the same period underneath, because "why is this subject weak" is very
/// often answered by how many days the child was there.
///
/// Nothing on this page is invented: a subject with no mark, a term with
/// nothing before it and a period with no working day all read as a dash.
class StudentPerformanceDialog extends ConsumerWidget {
  const StudentPerformanceDialog({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studentPerformanceProvider(student.id));

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
                ],
                const SizedBox(height: 20),
                _Attendance(performance: performance),
              ],
            ),
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
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
