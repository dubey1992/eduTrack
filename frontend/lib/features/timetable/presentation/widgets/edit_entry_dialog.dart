import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../subjects/data/models/subject.dart';
import '../../../users/application/teacher_picker_provider.dart';
import '../../../users/data/models/app_user.dart';
import '../../application/subject_picker_provider.dart';
import '../../application/timetable_grid_notifier.dart';
import '../../data/models/day_of_week.dart';
import '../../data/models/timetable_entry.dart';

/// Assigns (or clears) the subject/teacher for one class section's single
/// day+period cell - the prototype's "Edit Timetable" interaction, done one
/// cell at a time rather than as a whole-week form.
class EditEntryDialog extends ConsumerStatefulWidget {
  const EditEntryDialog({
    super.key,
    required this.schoolId,
    required this.classSectionId,
    required this.periodId,
    required this.periodLabel,
    required this.dayOfWeek,
    this.existing,
  });

  final int? schoolId;
  final int classSectionId;
  final int periodId;
  final String periodLabel;
  final DayOfWeek dayOfWeek;

  /// Null when the cell is currently empty.
  final TimetableEntry? existing;

  @override
  ConsumerState<EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends ConsumerState<EditEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  int? _subjectId;
  int? _teacherId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _subjectId = widget.existing?.subjectId;
    _teacherId = widget.existing?.teacherId;
  }

  TimetableGridParams get _gridParams => TimetableGridParams.forClassSection(widget.classSectionId);

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(timetableGridProvider(_gridParams).notifier)
          .upsertCell(
            schoolId: widget.schoolId,
            periodId: widget.periodId,
            dayOfWeek: widget.dayOfWeek,
            subjectId: _subjectId!,
            teacherId: _teacherId!,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _clear() async {
    final existing = widget.existing;
    if (existing == null) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(timetableGridProvider(_gridParams).notifier).deleteCell(existing);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjectsState = ref.watch(subjectPickerProvider(widget.schoolId));
    final teachersState = ref.watch(teacherPickerProvider(widget.schoolId));

    return AlertDialog(
      title: Text('${widget.periodLabel} · ${widget.dayOfWeek.label}'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              AsyncValueView<List<Subject>>(
                value: subjectsState,
                data: (context, subjects) {
                  return DropdownButtonFormField<int>(
                    initialValue: subjects.any((s) => s.id == _subjectId) ? _subjectId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: [
                      for (final subject in subjects) DropdownMenuItem(value: subject.id, child: Text(subject.name)),
                    ],
                    onChanged: (value) => setState(() => _subjectId = value),
                    validator: (v) => v == null ? 'Subject is required' : null,
                  );
                },
              ),
              const SizedBox(height: 10),
              AsyncValueView<List<AppUser>>(
                value: teachersState,
                data: (context, teachers) {
                  return DropdownButtonFormField<int>(
                    initialValue: teachers.any((t) => t.id == _teacherId) ? _teacherId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Teacher'),
                    items: [
                      for (final teacher in teachers) DropdownMenuItem(value: teacher.id, child: Text(teacher.name)),
                    ],
                    onChanged: (value) => setState(() => _teacherId = value),
                    validator: (v) => v == null ? 'Teacher is required' : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null) TextButton(onPressed: _isSubmitting ? null : _clear, child: const Text('Clear')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
