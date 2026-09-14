import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/password_field.dart';
import '../application/auth_notifier.dart';

/// Where an account lands when it was created by a bulk import and handed a
/// generated password. The router holds it here - there is no sidebar and no
/// way past - until it picks a password of its own.
///
/// The same screen is reachable on purpose from the account menu, for
/// anybody who simply wants to change theirs.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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
          .read(authNotifierProvider.notifier)
          .changePassword(currentPassword: _currentController.text, password: _passwordController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
        context.go('/dashboard');
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
    final mustChange = ref.watch(authNotifierProvider).value?.mustChangePassword ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        // Nothing to go back to while the change is being required.
        automaticallyImplyLeading: !mustChange,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mustChange
                            ? 'Your account was set up with a temporary password. Choose your own to continue.'
                            : 'Choose a new password for your account.',
                      ),
                      const SizedBox(height: 18),
                      if (_errorMessage != null) ...[
                        Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                        const SizedBox(height: 12),
                      ],
                      PasswordField(
                        controller: _currentController,
                        label: 'Current password',
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
                      ),
                      const SizedBox(height: 10),
                      PasswordField(
                        controller: _passwordController,
                        label: 'New password',
                        helperText: 'At least 8 characters.',
                      ),
                      const SizedBox(height: 10),
                      PasswordField(
                        controller: _confirmController,
                        label: 'Confirm new password',
                        validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Change Password'),
                        ),
                      ),
                      if (mustChange) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: _isSubmitting ? null : () => ref.read(authNotifierProvider.notifier).logout(),
                            child: const Text('Sign out instead'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
