import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/school_clock_provider.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../auth/application/auth_notifier.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../schools/data/models/school.dart';
import '../application/staff_list_notifier.dart';

const _staffRoles = [UserRole.teacher, UserRole.hod, UserRole.staff, UserRole.transportManager];

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
  bool _obscurePassword = true;

  bool _isSubmitting = false;
  String? _errorMessage;

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
    });

    try {
      await ref
          .read(staffListNotifierProvider.notifier)
          .createEmployee(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
            password: _passwordController.text,
            role: _role,
            schoolId: _schoolId,
            employeeId: _employeeIdController.text.trim(),
            departmentId: _departmentId,
            designation: _designationController.text.trim().isEmpty ? null : _designationController.text.trim(),
            joiningDate: _joiningDate,
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee added.')));
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
                if (isSuperAdmin) ...[
                  _SchoolPicker(
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
                PhoneNumberField(controller: _mobileController, label: 'Mobile (optional)'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickJoiningDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Joining date'),
                    child: Text(DateFormat.yMMMd().format(_joiningDate)),
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
