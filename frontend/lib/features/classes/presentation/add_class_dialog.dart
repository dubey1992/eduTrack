import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/school_class_list_notifier.dart';
import '../data/class_levels.dart';
import 'class_level_field.dart';
import '../../../core/widgets/school_picker.dart';

class AddClassDialog extends ConsumerStatefulWidget {
  const AddClassDialog({super.key});

  @override
  ConsumerState<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends ConsumerState<AddClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  int? _schoolId;
  int? _academicYearId;
  int? _level;
  bool _levelPicked = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// "LKG" or "Class 7" says which year it is; a year picked by hand stays.
  void _nameChanged(String name) {
    if (_levelPicked) return;
    final inferred = classLevelFromName(name);
    if (inferred != _level) setState(() => _level = inferred);
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
            level: _level!,
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
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;

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
                if (picksSchool) ...[
                  SchoolPicker(
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
                  decoration: const InputDecoration(labelText: 'Class name (e.g. Class 8 or LKG)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  onChanged: _nameChanged,
                ),
                const SizedBox(height: 10),
                ClassLevelField(
                  value: _level,
                  helperText: 'Sets the class order and where promotion moves students.',
                  onChanged: (value) => setState(() {
                    _level = value;
                    _levelPicked = true;
                  }),
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
