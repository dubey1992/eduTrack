import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
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
  const ChangePasswordForm({super.key, required this.onChanged, this.intro, this.submitLabel, this.footer});

  /// Called once the password has actually been changed. The dialog closes
  /// itself; the screen navigates on.
  final VoidCallback onChanged;

  /// A line above the fields explaining why they are here, if anything needs
  /// explaining.
  final String? intro;

  /// The button's words; "Change Password" when not given.
  final String? submitLabel;

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
      if (mounted) setState(() => _errorMessage = failure.localizedMessage(context));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
            label: l10n.staffCurrentPassword,
            validator: (v) => (v == null || v.isEmpty) ? l10n.staffEnterCurrentPassword : null,
          ),
          const SizedBox(height: 10),
          PasswordField(
            controller: _passwordController,
            label: l10n.staffNewPassword,
            helperText: l10n.staffNewPasswordHint,
          ),
          const SizedBox(height: 10),
          PasswordField(
            controller: _confirmController,
            label: l10n.staffConfirmNewPassword,
            validator: (v) => v != _passwordController.text ? l10n.staffPasswordsDoNotMatch : null,
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : submit,
              child: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.submitLabel ?? l10n.staffChangePasswordTitle),
            ),
          ),
          if (widget.footer != null) ...[const SizedBox(height: 12), widget.footer!(context, _isSubmitting)],
        ],
      ),
    );
  }
}
