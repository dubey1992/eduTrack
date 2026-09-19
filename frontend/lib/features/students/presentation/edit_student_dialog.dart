import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/student_list_notifier.dart';
import '../data/models/student.dart';
import 'widgets/student_transport_picker.dart';

class EditStudentDialog extends ConsumerStatefulWidget {
  const EditStudentDialog({super.key, required this.student});

  final Student student;

  @override
  ConsumerState<EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends ConsumerState<EditStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _rollNumberController = TextEditingController(text: widget.student.rollNumber ?? '');
  late final _guardianNameController = TextEditingController(text: widget.student.guardianName);
  late final _guardianMobileController = TextEditingController(text: widget.student.guardianMobile ?? '');
  late final _guardianEmailController = TextEditingController(text: widget.student.guardianEmail ?? '');
  late final _studentMobileController = TextEditingController(text: widget.student.studentMobile ?? '');
  late final _studentEmailController = TextEditingController(text: widget.student.studentEmail ?? '');
  late final _addressController = TextEditingController(text: widget.student.address ?? '');

  late int? _classSectionId = widget.student.classSectionId;
  late int? _routeId = widget.student.transport?.routeId;
  late int? _stopId = widget.student.transport?.stopId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _rollNumberController.dispose();
    _guardianNameController.dispose();
    _guardianMobileController.dispose();
    _guardianEmailController.dispose();
    _studentMobileController.dispose();
    _studentEmailController.dispose();
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
          .updateStudent(
            widget.student,
            classSectionId: _classSectionId,
            rollNumber: _rollNumberController.text.trim().isEmpty ? null : _rollNumberController.text.trim(),
            guardianName: _guardianNameController.text.trim(),
            guardianMobile: _guardianMobileController.text.trim().isEmpty
                ? null
                : _guardianMobileController.text.trim(),
            guardianEmail: _optionalText(_guardianEmailController),
            studentMobile: _optionalText(_studentMobileController),
            studentEmail: _optionalText(_studentEmailController),
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
            routeId: _routeId,
            stopId: _stopId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student updated.')));
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
      title: Text('Edit ${widget.student.name}'),
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
                _ClassSectionPicker(
                  schoolId: widget.student.schoolId,
                  selected: _classSectionId,
                  onChanged: (value) => setState(() => _classSectionId = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _rollNumberController,
                  decoration: const InputDecoration(labelText: 'Roll number (optional)'),
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
                  controller: _guardianEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Parent email (optional)'),
                  validator: _optionalEmailProblem,
                ),
                const SizedBox(height: 10),
                PhoneNumberField(controller: _studentMobileController, label: 'Student mobile (optional)'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _studentEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Student email (optional)'),
                  validator: _optionalEmailProblem,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                StudentTransportPicker(
                  schoolId: null,
                  routeId: _routeId,
                  stopId: _stopId,
                  currentRouteLabel: widget.student.transport?.routeLabel,
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// An optional field's text, or null when it was left empty.
String? _optionalText(TextEditingController controller) {
  final text = controller.text.trim();
  return text.isEmpty ? null : text;
}

/// Optional, but an email if anything is typed.
String? _optionalEmailProblem(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty || text.contains('@')) return null;
  return 'Enter a valid email';
}

class _ClassSectionPicker extends ConsumerWidget {
  const _ClassSectionPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int schoolId;
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
