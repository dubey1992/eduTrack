import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../users/application/teacher_picker_provider.dart';
import '../../users/data/models/app_user.dart';
import '../application/school_class_list_notifier.dart';
import '../data/models/school_class.dart';

class EditSectionDialog extends ConsumerStatefulWidget {
  const EditSectionDialog({super.key, required this.schoolId, required this.section});

  final int schoolId;
  final ClassSection section;

  @override
  ConsumerState<EditSectionDialog> createState() => _EditSectionDialogState();
}

class _EditSectionDialogState extends ConsumerState<EditSectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.section.name);
  late final _roomController = TextEditingController(text: widget.section.roomNumber ?? '');

  late int? _classTeacherId = widget.section.classTeacherId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
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
          .read(schoolClassListNotifierProvider.notifier)
          .updateSection(
            widget.section,
            name: _nameController.text.trim().toUpperCase(),
            roomNumber: _roomController.text.trim().isEmpty ? null : _roomController.text.trim(),
            classTeacherId: _classTeacherId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section updated.')));
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
      title: Text('Edit Section ${widget.section.name}'),
      content: SizedBox(
        width: 400,
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
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Section (e.g. A)'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Section name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(labelText: 'Room number (optional)'),
                ),
                const SizedBox(height: 10),
                _ClassTeacherPicker(
                  schoolId: widget.schoolId,
                  selected: _classTeacherId,
                  onChanged: (value) => setState(() => _classTeacherId = value),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _ClassTeacherPicker extends ConsumerWidget {
  const _ClassTeacherPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teachersState = ref.watch(teacherPickerProvider(schoolId));

    return AsyncValueView<List<AppUser>>(
      value: teachersState,
      data: (context, teachers) {
        return DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class teacher (optional)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No class teacher assigned')),
            for (final teacher in teachers) DropdownMenuItem(value: teacher.id, child: Text(teacher.name)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}
