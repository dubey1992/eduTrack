import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/password_field.dart';
import '../application/profile_notifier.dart';

/// Changes the address the user signs in with.
///
/// Asks for the current password, because whoever holds the email holds the
/// account. Pops with true on success - the server has by then signed every
/// other device out. A refusal stays in the dialog, under the field it is
/// about.
class ChangeEmailDialog extends ConsumerStatefulWidget {
  const ChangeEmailDialog({super.key, required this.currentEmail});

  final String currentEmail;

  @override
  ConsumerState<ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends ConsumerState<ChangeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await ref
          .read(profileNotifierProvider.notifier)
          .changeEmail(email: _emailController.text.trim(), currentPassword: _passwordController.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // A message already shown under a field is not repeated below.
          _error = _fieldErrors.isEmpty ? failure.localizedMessage(context) : null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final passwordError = _serverError('current_password');
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffChangeSignInEmail),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.staffYouSignInAs(widget.currentEmail)),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('change-email-new'),
                  controller: _emailController,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: l10n.staffNewEmail, errorText: _serverError('email')),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return l10n.staffEnterNewEmail;
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) return l10n.staffEnterValidEmail;
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                PasswordField(
                  key: const Key('change-email-password'),
                  controller: _passwordController,
                  label: l10n.staffCurrentPassword,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => (v == null || v.isEmpty) ? l10n.staffEnterCurrentPassword : null,
                ),
                if (passwordError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(passwordError, style: TextStyle(fontSize: 12, color: colors.danger)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: colors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(l10n.staffChangeEmail),
        ),
      ],
    );
  }
}
