import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../auth/application/auth_notifier.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../schools/data/models/school.dart';
import '../application/school_class_list_notifier.dart';

class AddClassDialog extends ConsumerStatefulWidget {
  const AddClassDialog({super.key});

  @override
  ConsumerState<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends ConsumerState<AddClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _levelController = TextEditingController();

  int? _schoolId;
  int? _academicYearId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _levelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate() || _academicYearId == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(schoolClassListNotifierProvider.notifier)
          .createClass(
            schoolId: _schoolId,
            academicYearId: _academicYearId!,
            name: _nameController.text.trim(),
            level: int.parse(_levelController.text),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class created.')));
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
    final isSuperAdmin = ref.watch(authNotifierProvider).value?.role == UserRole.superAdmin;

    return AlertDialog(
      title: const Text('Add Class'),
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
                if (isSuperAdmin) ...[
                  _SchoolPicker(
                    selected: _schoolId,
                    onChanged: (value) => setState(() {
                      _schoolId = value;
                      _academicYearId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                _AcademicYearPicker(
                  schoolId: _schoolId,
                  selected: _academicYearId,
                  onChanged: (value) => setState(() => _academicYearId = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Grade / Class (e.g. Grade 8)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _levelController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Level (0-12)'),
                  validator: (v) {
                    final parsed = int.tryParse(v ?? '');
                    if (parsed == null || parsed < 0 || parsed > 12) return 'Enter a level between 0 and 12';
                    return null;
                  },
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

class _SchoolPicker extends ConsumerWidget {
  const _SchoolPicker({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolsState = ref.watch(schoolListNotifierProvider);

    return AsyncValueView<List<School>>(
      value: schoolsState,
      data: (context, schools) {
        final activeSchools = schools.where((s) => s.status == SchoolStatus.active);
        return DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'School'),
          items: [
            for (final school in activeSchools)
              DropdownMenuItem(
                value: school.id,
                child: Text(school.name, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
          ],
          onChanged: onChanged,
          validator: (v) => v == null ? 'School is required' : null,
        );
      },
    );
  }
}

class _AcademicYearPicker extends ConsumerWidget {
  const _AcademicYearPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearsState = ref.watch(academicYearPickerProvider(schoolId));

    return AsyncValueView<List<AcademicYear>>(
      value: yearsState,
      data: (context, years) {
        return DropdownButtonFormField<int>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Academic year'),
          items: [for (final year in years) DropdownMenuItem(value: year.id, child: Text(year.name))],
          onChanged: onChanged,
          validator: (v) => v == null ? 'Academic year is required' : null,
        );
      },
    );
  }
}
