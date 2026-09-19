import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../application/staff_list_notifier.dart';
import '../data/models/staff_profile.dart';
import 'attendant_sign_in_dialog.dart';
import 'widgets/staff_email_text.dart';
import '../../../core/utils/date_format.dart';

class EditStaffProfileDialog extends ConsumerStatefulWidget {
  const EditStaffProfileDialog({super.key, required this.profile});

  final StaffProfile profile;

  @override
  ConsumerState<EditStaffProfileDialog> createState() => _EditStaffProfileDialogState();
}

class _EditStaffProfileDialogState extends ConsumerState<EditStaffProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _employeeIdController = TextEditingController(text: widget.profile.employeeId);
  late final _designationController = TextEditingController(text: widget.profile.designation ?? '');
  late final _addressController = TextEditingController(text: widget.profile.address ?? '');

  late int? _departmentId = widget.profile.departmentId;
  late DateTime _joiningDate = widget.profile.joiningDate;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _employeeIdController.dispose();
    _designationController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickJoiningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joiningDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _joiningDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(staffListNotifierProvider.notifier)
          .updateProfile(
            widget.profile,
            employeeId: _employeeIdController.text.trim(),
            departmentId: _departmentId,
            designation: _designationController.text.trim().isEmpty ? null : _designationController.text.trim(),
            joiningDate: _joiningDate,
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff profile updated.')));
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
      title: Text('Edit ${widget.profile.name}'),
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
                _AccountSummary(profile: widget.profile),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _employeeIdController,
                  decoration: const InputDecoration(labelText: 'Employee ID'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                _DepartmentPicker(
                  schoolId: widget.profile.schoolId,
                  selected: _departmentId,
                  onChanged: (value) => setState(() => _departmentId = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _designationController,
                  decoration: const InputDecoration(labelText: 'Designation (optional)'),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickJoiningDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Joining date'),
                    child: Text(formatDate(_joiningDate)),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _DepartmentPicker extends ConsumerWidget {
  const _DepartmentPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int schoolId;
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
          decoration: const InputDecoration(labelText: 'Department (optional)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No department')),
            for (final department in departments) DropdownMenuItem(value: department.id, child: Text(department.name)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

/// The account half of the employee, read-only here: the email (or "No
/// email"), and for a Bus Attendant the way into their sign-in panel.
class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.profile});

  final StaffProfile profile;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.email_outlined, size: 18, color: muted),
            const SizedBox(width: 8),
            Expanded(child: StaffEmailText(profile: profile)),
          ],
        ),
        if (profile.isBusAttendant) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AttendantSignInDialog(profile: profile),
            ),
            icon: const Icon(Icons.phonelink_lock_outlined, size: 18),
            label: const Text('Sign-in & phones'),
          ),
        ],
      ],
    );
  }
}
