import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/syllabus_checklist_notifier.dart';
import '../../data/syllabus_topic_repository.dart';

/// Adds one topic to a subject's curriculum outline. [nextSequenceNumber]
/// pre-fills the position field with "next after the last one" - the
/// common case - but it's still editable, so a topic can be inserted
/// anywhere by typing a different number.
class AddTopicDialog extends ConsumerStatefulWidget {
  const AddTopicDialog({
    super.key,
    required this.schoolId,
    required this.subjectId,
    required this.params,
    required this.nextSequenceNumber,
  });

  final int? schoolId;
  final int subjectId;
  final SyllabusChecklistParams params;
  final int nextSequenceNumber;

  @override
  ConsumerState<AddTopicDialog> createState() => _AddTopicDialogState();
}

class _AddTopicDialogState extends ConsumerState<AddTopicDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  late final _sequenceController = TextEditingController(text: '${widget.nextSequenceNumber}');

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _sequenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(syllabusTopicRepositoryProvider)
          .create(
            schoolId: widget.schoolId,
            subjectId: widget.subjectId,
            title: _titleController.text.trim(),
            sequenceNumber: int.parse(_sequenceController.text.trim()),
          );
      await ref.read(syllabusChecklistProvider(widget.params).notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Topic added.')));
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
      title: const Text('Add Topic'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Topic title'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _sequenceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Position in outline'),
                validator: (v) {
                  final parsed = int.tryParse(v?.trim() ?? '');
                  return (parsed == null || parsed < 1) ? 'Enter a valid position' : null;
                },
              ),
            ],
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
              : const Text('Add'),
        ),
      ],
    );
  }
}
