import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../data/auth_repository.dart';
import 'teacher_auth_shell.dart';

/// Asking for a password reset link from the Teacher app.
///
/// The server answers the same way whether or not the address has an
/// account, so this screen does too: it never says "no such teacher".
class TeacherForgotPasswordScreen extends ConsumerStatefulWidget {
  const TeacherForgotPasswordScreen({super.key});

  @override
  ConsumerState<TeacherForgotPasswordScreen> createState() => _TeacherForgotPasswordScreenState();
}

class _TeacherForgotPasswordScreenState extends ConsumerState<TeacherForgotPasswordScreen> {
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isSubmitting = false;
  String? _sentTo;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final email = _emailController.text.trim();

    try {
      await ref.read(authRepositoryProvider).forgotPassword(email);
      if (mounted) setState(() => _sentTo = email);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TeacherAuthShell(
      title: _sentTo == null ? 'Reset your password' : 'Check your email',
      subtitle: _sentTo == null
          ? 'Enter your school email and we will send you a link to choose a new password.'
          : 'A link to choose a new password is on its way.',
      onBack: () => context.go('/login'),
      child: _sentTo != null
          ? Column(
              key: const Key('forgot-sent'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_read_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'If an account exists for $_sentTo, the email is on its way. The link works once and '
                  'lasts one hour. If it does not arrive, look in your spam folder.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 10),
                Text(
                  'Choose your new password from the link, then come back here and sign in with it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 24),
                TeacherPrimaryButton(
                  key: const Key('forgot-back-to-sign-in'),
                  label: 'Back to sign in',
                  onPressed: () => context.go('/login'),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    TeacherErrorBanner(key: const Key('forgot-error'), message: _error!),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    key: const Key('forgot-email'),
                    controller: _emailController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.send,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return 'Enter your email.';
                      if (!_emailShape.hasMatch(email)) return 'That does not look like an email address.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  TeacherPrimaryButton(
                    key: const Key('forgot-submit'),
                    label: 'Send reset link',
                    busy: _isSubmitting,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
    );
  }
}
