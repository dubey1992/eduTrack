import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
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
