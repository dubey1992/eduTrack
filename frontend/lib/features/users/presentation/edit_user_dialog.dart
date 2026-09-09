import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/user_list_notifier.dart';
import '../data/models/app_user.dart';

/// Roles a SCHOOL_ADMIN may assign - mirrors the backend's
/// UpdateUserRequest::SCHOOL_ADMIN_ASSIGNABLE_ROLES.
const _schoolAdminAssignableRoles = [UserRole.hod, UserRole.teacher, UserRole.staff, UserRole.transportManager];

class EditUserDialog extends ConsumerStatefulWidget {
  const EditUserDialog({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameController = TextEditingController(text: widget.user.firstName);
  late final _lastNameController = TextEditingController(text: widget.user.lastName);
  late final _emailController = TextEditingController(text: widget.user.email);
  late final _mobileController = TextEditingController(text: widget.user.mobile ?? '');
  final _passwordController = TextEditingController();
  late UserRole _role = widget.user.role;

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
          .updateUser(
            widget.user,
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
            password: _passwordController.text.isEmpty ? null : _passwordController.text,
            role: _role,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated.')));
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
    final assignableRoles = isSuperAdmin ? UserRole.values : _schoolAdminAssignableRoles;

    return AlertDialog(
      title: Text('Edit ${widget.user.name}'),
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
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password (leave blank to keep current)'),
                  validator: (v) => (v != null && v.isNotEmpty && v.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<UserRole>(
                  initialValue: assignableRoles.contains(_role) ? _role : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [for (final role in assignableRoles) DropdownMenuItem(value: role, child: Text(role.label))],
                  onChanged: (value) => setState(() => _role = value ?? _role),
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
