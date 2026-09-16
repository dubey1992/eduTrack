import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../auth/application/auth_notifier.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/student_list_notifier.dart';
import 'widgets/student_transport_picker.dart';
import '../../../core/widgets/school_picker.dart';

class AddStudentDialog extends ConsumerStatefulWidget {
  const AddStudentDialog({super.key});

  @override
  ConsumerState<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends ConsumerState<AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _admissionNumberController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _rollNumberController = TextEditingController();
  final _guardianNameController = TextEditingController();
  final _guardianMobileController = TextEditingController();
  final _addressController = TextEditingController();

  int? _schoolId;
  int? _classSectionId;
  int? _routeId;
  int? _stopId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _admissionNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _rollNumberController.dispose();
    _guardianNameController.dispose();
    _guardianMobileController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate() || _classSectionId == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(studentListNotifierProvider.notifier)
          .createStudent(
            schoolId: _schoolId,
            classSectionId: _classSectionId!,
            admissionNumber: _admissionNumberController.text.trim(),
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            rollNumber: _rollNumberController.text.trim().isEmpty ? null : _rollNumberController.text.trim(),
            guardianName: _guardianNameController.text.trim(),
            guardianMobile: _guardianMobileController.text.trim().isEmpty
                ? null
                : _guardianMobileController.text.trim(),
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
            routeId: _routeId,
            stopId: _stopId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student admitted.')));
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
      title: const Text('Add Student'),
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
                      _classSectionId = null;
                      _routeId = null;
                      _stopId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'First name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameController,
                        decoration: const InputDecoration(labelText: 'Last name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _admissionNumberController,
                        decoration: const InputDecoration(labelText: 'Admission ID'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _rollNumberController,
                        decoration: const InputDecoration(labelText: 'Roll number (optional)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ClassSectionPicker(
                  schoolId: _schoolId,
                  selected: _classSectionId,
                  onChanged: (value) => setState(() => _classSectionId = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _guardianNameController,
                  decoration: const InputDecoration(labelText: 'Parent / Guardian'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                PhoneNumberField(controller: _guardianMobileController, label: 'Parent mobile (optional)'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                StudentTransportPicker(
                  schoolId: _schoolId,
                  routeId: _routeId,
                  stopId: _stopId,
                  currentRouteLabel: null,
                  onChanged: (routeId, stopId) => setState(() {
                    _routeId = routeId;
                    _stopId = stopId;
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
              : const Text('Save Student'),
        ),
      ],
    );
  }
}

class _ClassSectionPicker extends ConsumerWidget {
  const _ClassSectionPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsState = ref.watch(classSectionPickerProvider(schoolId));

    return AsyncValueView<List<ClassSectionOption>>(
      value: optionsState,
      data: (context, options) {
        return DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [for (final option in options) DropdownMenuItem(value: option.id, child: Text(option.label))],
          onChanged: onChanged,
          validator: (v) => v == null ? 'Class is required' : null,
        );
      },
    );
  }
}
