import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/school_clock_provider.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../auth/application/auth_notifier.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../application/staff_list_notifier.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/school_picker.dart';

const _staffRoles = [
  UserRole.teacher,
  UserRole.hod,
  UserRole.staff,
  UserRole.transportManager,
  UserRole.accountant,
  UserRole.busAttendant,
];

class AddStaffDialog extends ConsumerStatefulWidget {
  const AddStaffDialog({super.key});

  @override
  ConsumerState<AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends ConsumerState<AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _designationController = TextEditingController();
  final _addressController = TextEditingController();

  UserRole _role = UserRole.teacher;
  int? _schoolId;
  int? _departmentId;
  late DateTime _joiningDate;

  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  /// A Bus Attendant signs in with their mobile number and a passcode on a
  /// registered phone, so the form asks for the mobile, makes the email
  /// optional and has no password at all (docs/maps.md).
  bool get _isAttendant => _role == UserRole.busAttendant;

  String? _serverError(String field) => _fieldErrors[field]?.first;

  @override
  void initState() {
    super.initState();
    _joiningDate = ref.read(schoolClockProvider).today;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _employeeIdController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
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
      _fieldErrors = const {};
    });

    final email = _emailController.text.trim();

    try {
      await ref
          .read(staffListNotifierProvider.notifier)
          .createEmployee(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: email.isEmpty ? null : email,
            mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
            password: _isAttendant ? null : _passwordController.text,
            role: _role,
            schoolId: _schoolId,
            employeeId: _employeeIdController.text.trim(),
            departmentId: _departmentId,
            designation: _designationController.text.trim().isEmpty ? null : _designationController.text.trim(),
            joiningDate: _joiningDate,
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAttendant
                  ? 'Bus Attendant added. Open their Sign-in to issue a setup code for their phone.'
                  : 'Employee added.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // A message that belongs to a field is shown under that field;
          // anything else goes at the top of the form.
          final shownByField = _serverError('mobile') != null || _serverError('email') != null;
          _errorMessage = shownByField ? null : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;

    return AlertDialog(
      title: const Text('Add Teacher / Staff'),
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
                        controller: _employeeIdController,
                        decoration: const InputDecoration(labelText: 'Employee ID'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<UserRole>(
                        initialValue: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          for (final role in _staffRoles)
                            DropdownMenuItem(
                              value: role,
                              child: Text(role.label, overflow: TextOverflow.ellipsis, maxLines: 1),
                            ),
                        ],
                        onChanged: (value) => setState(() => _role = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (picksSchool) ...[
                  SchoolPicker(
                    selected: _schoolId,
                    onChanged: (value) => setState(() {
                      _schoolId = value;
                      _departmentId = null;
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
                TextFormField(
                  controller: _designationController,
                  decoration: const InputDecoration(labelText: 'Designation (optional, e.g. Office Staff)'),
                ),
                const SizedBox(height: 10),
                PhoneNumberField(
                  controller: _mobileController,
                  label: _isAttendant ? 'Mobile' : 'Mobile (optional)',
                  required: _isAttendant,
                ),
                if (_serverError('mobile') != null) _FieldError(_serverError('mobile')!),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: _isAttendant ? 'Email (optional)' : 'Email',
                    errorText: _serverError('email'),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (_isAttendant && value.isEmpty) return null;
                    return value.contains('@') ? null : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 10),
                if (_isAttendant)
                  const _AttendantSignInNote()
                else
                  PasswordField(controller: _passwordController, helperText: newPasswordHint),
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

/// A server-side validation message under a field that cannot carry an
/// errorText of its own (the composite phone field).
class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(message, style: TextStyle(color: context.appColors.danger, fontSize: 12)),
      ),
    );
  }
}

/// Stands where the password field would be, saying why there is none.
class _AttendantSignInNote extends StatelessWidget {
  const _AttendantSignInNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'No password: a Bus Attendant signs in with this mobile number and a 4-digit passcode on a '
            'registered phone. After saving, open their Sign-in to issue a setup code.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
