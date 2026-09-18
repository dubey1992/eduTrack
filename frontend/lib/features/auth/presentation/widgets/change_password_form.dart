import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/password_field.dart';
import '../../application/auth_notifier.dart';

/// The three fields and the rules behind them, with nothing said about where
/// they are shown.
///
/// Two places need exactly this: the dialog somebody opens from the header
/// because they feel like changing their password, and the full screen the
/// router holds an imported account on until it does. Same form, same
/// validation, same error handling - only the frame differs.
class ChangePasswordForm extends ConsumerStatefulWidget {
  const ChangePasswordForm({
    super.key,
    required this.onChanged,
    this.intro,
    this.submitLabel = 'Change Password',
    this.footer,
  });

  /// Called once the password has actually been changed. The dialog closes
  /// itself; the screen navigates on.
  final VoidCallback onChanged;

  /// A line above the fields explaining why they are here, if anything needs
  /// explaining.
  final String? intro;

  final String submitLabel;

  /// Anything to sit below the button - "Sign out instead", a Cancel.
  /// Given [ChangePasswordFormState.isSubmitting] so it can disable itself.
  final Widget Function(BuildContext context, bool isSubmitting)? footer;

  @override
  ConsumerState<ChangePasswordForm> createState() => ChangePasswordFormState();
}

class ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isSubmitting => _isSubmitting;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .changePassword(currentPassword: _currentController.text, password: _passwordController.text);

      if (mounted) widget.onChanged();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.intro != null) ...[Text(widget.intro!), const SizedBox(height: 18)],
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
          PasswordField(controller: _passwordController, label: 'New password', helperText: newPasswordHint),
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
              onPressed: _isSubmitting ? null : submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.submitLabel),
            ),
          ),
          if (widget.footer != null) ...[const SizedBox(height: 12), widget.footer!(context, _isSubmitting)],
        ],
      ),
    );
  }
}
