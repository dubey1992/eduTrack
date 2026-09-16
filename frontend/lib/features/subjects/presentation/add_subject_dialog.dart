import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/application/auth_notifier.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../../users/application/teacher_picker_provider.dart';
import '../../users/data/models/app_user.dart';
import '../application/subject_list_notifier.dart';
import '../../../core/widgets/school_picker.dart';

class AddSubjectDialog extends ConsumerStatefulWidget {
  const AddSubjectDialog({super.key});

  @override
  ConsumerState<AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends ConsumerState<AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _minLevelController = TextEditingController();
  final _maxLevelController = TextEditingController();

  int? _schoolId;
  int? _departmentId;
  int? _leadTeacherId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _minLevelController.dispose();
    _maxLevelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate() || _departmentId == null) return;

    final minLevel = int.parse(_minLevelController.text);
    final maxLevel = int.parse(_maxLevelController.text);
    if (maxLevel < minLevel) {
      setState(() => _errorMessage = 'The max class level must be at or above the min class level.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(subjectListNotifierProvider.notifier)
          .createSubject(
            schoolId: _schoolId,
            departmentId: _departmentId!,
            code: _codeController.text.trim().toUpperCase(),
            name: _nameController.text.trim(),
            minClassLevel: minLevel,
            maxClassLevel: maxLevel,
            leadTeacherId: _leadTeacherId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subject created.')));
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
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;

    return AlertDialog(
      title: const Text('Add Subject'),
      content: SizedBox(
        width: 460,
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
                if (picksSchool) ...[
                  SchoolPicker(
                    selected: _schoolId,
                    onChanged: (value) => setState(() {
                      _schoolId = value;
                      _departmentId = null;
                      _leadTeacherId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                _DepartmentPicker(
                  schoolId: _schoolId,
                  selected: _departmentId,
                  onChanged: (value) => setState(() => _departmentId = value),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(labelText: 'Code (e.g. MAT)'),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Subject name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minLevelController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Min class level'),
                        validator: _levelValidator,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _maxLevelController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Max class level'),
                        validator: _levelValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _LeadTeacherPicker(
                  schoolId: _schoolId,
                  selected: _leadTeacherId,
                  onChanged: (value) => setState(() => _leadTeacherId = value),
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

  String? _levelValidator(String? v) {
    final parsed = int.tryParse(v ?? '');
    if (parsed == null || parsed < 0 || parsed > 12) return '0-12';
    return null;
  }
}

class _DepartmentPicker extends ConsumerWidget {
  const _DepartmentPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departmentsState = ref.watch(departmentPickerProvider(schoolId));

    return AsyncValueView<List<Department>>(
      value: departmentsState,
      data: (context, departments) {
        return DropdownButtonFormField<int>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Department'),
          items: [
            for (final department in departments) DropdownMenuItem(value: department.id, child: Text(department.name)),
          ],
          onChanged: onChanged,
          validator: (v) => v == null ? 'Department is required' : null,
        );
      },
    );
  }
}

class _LeadTeacherPicker extends ConsumerWidget {
  const _LeadTeacherPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
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
          decoration: const InputDecoration(labelText: 'Lead teacher (optional)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No lead teacher assigned')),
            for (final teacher in teachers) DropdownMenuItem(value: teacher.id, child: Text(teacher.name)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}
