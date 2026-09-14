import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../auth/application/auth_notifier.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../schools/data/models/school.dart';
import '../application/user_list_notifier.dart';

/// Onboards an admin-tier account - always SCHOOL_ADMIN, the only role
/// this dialog creates (mirrors the backend's StoreUserRequest). A
/// SUPER_ADMIN actor creates a School Admin for a school they pick; a
/// (non-sub) School Admin actor creates a Sub Admin for their own school -
/// same role and permissions everywhere else, but the Sub Admin can't use
/// this dialog themselves (see UserPolicy::create()). HOD/Teacher/Staff/
/// Transport Manager accounts are onboarded via Teachers & Staff instead,
/// which creates the StaffProfile this dialog deliberately doesn't - a
/// Teacher created here would be invisible to Attendance/Leave.
class AddUserDialog extends ConsumerStatefulWidget {
  const AddUserDialog({super.key});

  @override
  ConsumerState<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  int? _schoolId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
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
          .read(userListNotifierProvider.notifier)
          .createUser(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
            password: _passwordController.text,
            role: UserRole.schoolAdmin,
            schoolId: _schoolId,
          );
      if (mounted) {
        final isSuperAdmin = ref.read(authNotifierProvider).value?.role == UserRole.superAdmin;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(isSuperAdmin ? 'School admin created.' : 'Sub admin created.')));
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
      title: Text(isSuperAdmin ? 'Add School Admin' : 'Add Sub Admin'),
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
                  controller: _firstNameController,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 10),
                PhoneNumberField(controller: _mobileController, label: 'Mobile (optional)'),
                const SizedBox(height: 10),
                PasswordField(controller: _passwordController, helperText: 'At least 8 characters.'),
                // A School Admin's Sub Admin always lands in their own
                // school, resolved server-side - no picker needed. Only a
                // SUPER_ADMIN, who has no "own school", must choose one.
                if (isSuperAdmin) ...[
                  const SizedBox(height: 10),
                  _SchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                ],
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
              : const Text('Create'),
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
