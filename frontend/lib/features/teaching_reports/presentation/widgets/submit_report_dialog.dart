import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../syllabus/data/models/syllabus_topic.dart';
import '../../../syllabus/data/syllabus_topic_repository.dart';
import '../../../timetable/data/models/timetable_entry.dart';
import '../../application/teaching_report_list_notifier.dart';

/// Files today's report for one of the actor's own scheduled periods - the
/// [entry] and [reportDate] are fixed (chosen by tapping a "My Teaching
/// Today" row), so there's no period/date picker here.
class SubmitReportDialog extends ConsumerStatefulWidget {
  const SubmitReportDialog({super.key, required this.entry, required this.reportDate});

  final TimetableEntry entry;
  final String reportDate;

  @override
  ConsumerState<SubmitReportDialog> createState() => _SubmitReportDialogState();
}

class _SubmitReportDialogState extends ConsumerState<SubmitReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final _homeworkController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  int? _syllabusTopicId;

  @override
  void dispose() {
    _topicController.dispose();
    _homeworkController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final params = TeachingReportListParams(teacherId: widget.entry.teacherId, reportDate: widget.reportDate);
      await ref
          .read(teachingReportListNotifierProvider(params).notifier)
          .submit(
            timetableEntryId: widget.entry.id,
            reportDate: widget.reportDate,
            topicTaught: _topicController.text.trim(),
            syllabusTopicId: _syllabusTopicId,
            homework: _homeworkController.text.trim().isEmpty ? null : _homeworkController.text.trim(),
            remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Submit Report - Period ${widget.entry.periodNumber ?? ''}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                Text(
                  '${widget.entry.subjectName ?? ''} · ${widget.entry.classSectionName ?? ''}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _topicController,
                  decoration: const InputDecoration(labelText: 'Topic taught'),
                  maxLines: 2,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Topic taught is required' : null,
                ),
                const SizedBox(height: 10),
                _TopicPicker(
                  subjectId: widget.entry.subjectId,
                  value: _syllabusTopicId,
                  onChanged: (id) => setState(() => _syllabusTopicId = id),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _homeworkController,
                  decoration: const InputDecoration(labelText: 'Homework (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}

/// The syllabus topics of the subject this period teaches.
///
/// Picking one marks it covered for the class when the report is filed, so
/// the teacher does not write the topic here and tick the same topic on the
/// Syllabus screen (docs/insights.md).
///
/// Optional on purpose: a revision period, a test or a visiting speaker is a
/// real lesson that belongs to no chapter, and "Topic taught" still says what
/// happened. A subject with no syllabus shows nothing rather than an empty
/// box somebody has to wonder about.
final _topicsProvider = FutureProvider.autoDispose.family<List<SyllabusTopic>, int>((ref, subjectId) {
  return ref.watch(syllabusTopicRepositoryProvider).list(subjectId: subjectId);
});

class _TopicPicker extends ConsumerWidget {
  const _TopicPicker({required this.subjectId, required this.value, required this.onChanged});

  final int subjectId;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A syllabus that cannot be loaded must not stop a report being filed,
    // so a failure here shows nothing rather than an error.
    return ref
        .watch(_topicsProvider(subjectId))
        .maybeWhen(
          data: (topics) {
            if (topics.isEmpty) return const SizedBox.shrink();

            return DropdownButtonFormField<int?>(
              key: const Key('report-syllabus-topic'),
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Syllabus topic (optional)',
                helperText: 'Picking one ticks it off for this class',
                helperMaxLines: 2,
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Not a syllabus topic')),
                for (final topic in topics) DropdownMenuItem<int?>(value: topic.id, child: Text(topic.title)),
              ],
              onChanged: onChanged,
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
  }
}
