import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../users/application/teacher_picker_provider.dart';
import '../../users/data/models/app_user.dart';
import '../application/department_list_notifier.dart';
import '../data/models/department.dart';

class EditDepartmentDialog extends ConsumerStatefulWidget {
  const EditDepartmentDialog({super.key, required this.department});

  final Department department;

  @override
  ConsumerState<EditDepartmentDialog> createState() => _EditDepartmentDialogState();
}

class _EditDepartmentDialogState extends ConsumerState<EditDepartmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.department.name);
  late int? _hodUserId = widget.department.hodUserId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
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
          .read(departmentPageNotifierProvider.notifier)
          .updateDepartment(widget.department, name: _nameController.text.trim(), hodUserId: _hodUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Department updated.')));
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
      title: Text('Edit ${widget.department.name}'),
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
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Department name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                _HodPicker(
                  schoolId: widget.department.schoolId,
                  selected: _hodUserId,
                  onChanged: (value) => setState(() => _hodUserId = value),
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

class _HodPicker extends ConsumerWidget {
  const _HodPicker({required this.schoolId, required this.selected, required this.onChanged});

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
          decoration: const InputDecoration(labelText: 'HOD (optional)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No HOD assigned')),
            for (final teacher in teachers) DropdownMenuItem(value: teacher.id, child: Text(teacher.name)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}
