import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/network/dio_client.dart';
import '../../application/auth_notifier.dart';
import 'teacher_auth_shell.dart';

/// Signing in to the Teacher app (docs/teacher-app.md).
///
/// The same account and the same call as the web portal - email and
/// password - on a screen made for a phone: the keyboard's own email and
/// password keys, the password manager's autofill, the failure said in a
/// banner that stays until the next attempt. Where it goes once signed in is
/// the router's decision, not this screen's.
class TeacherSignInScreen extends ConsumerStatefulWidget {
  const TeacherSignInScreen({super.key});

  @override
  ConsumerState<TeacherSignInScreen> createState() => _TeacherSignInScreenState();
}

class _TeacherSignInScreenState extends ConsumerState<TeacherSignInScreen> {
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _rememberEmail = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final email = await ref.read(authTokenStorageProvider).readRememberedEmail();
    if (email == null || !mounted) return;
    setState(() => _emailController.text = email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final email = _emailController.text.trim();
    final notifier = ref.read(authNotifierProvider.notifier);
    await notifier.login(email: email, password: _passwordController.text);

    final result = ref.read(authNotifierProvider);
    final storage = ref.read(authTokenStorageProvider);

    if (result.hasError) {
      final error = result.error;
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _error = failure.message;
          _isSubmitting = false;
        });
      }
      return;
    }

    if (_rememberEmail) {
      await storage.saveRememberedEmail(email);
    } else {
      await storage.clearRememberedEmail();
    }

    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TeacherAuthShell(
      title: 'Welcome back',
      subtitle: 'Sign in with your school email and password.',
      onBack: () => context.go('/welcome'),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                TeacherErrorBanner(key: const Key('sign-in-error'), message: _error!),
                const SizedBox(height: 16),
              ],
              TextFormField(
                key: const Key('sign-in-email'),
                controller: _emailController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Enter your email.';
                  if (!_emailShape.hasMatch(email)) return 'That does not look like an email address.';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('sign-in-password'),
                controller: _passwordController,
                focusNode: _passwordFocus,
                enabled: !_isSubmitting,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (value) => (value == null || value.isEmpty) ? 'Enter your password.' : null,
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    key: const Key('sign-in-remember'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _rememberEmail = !_rememberEmail),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _rememberEmail,
                          onChanged: (value) => setState(() => _rememberEmail = value ?? false),
                        ),
                        // Flexible so a phone set to large text wraps the
                        // label rather than pushing it off the edge.
                        const Flexible(child: Text('Remember my email')),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('sign-in-forgot'),
                    onPressed: _isSubmitting ? null : () => context.go('/forgot-password'),
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TeacherPrimaryButton(
                key: const Key('sign-in-submit'),
                label: 'Sign in',
                busy: _isSubmitting,
                onPressed: _submit,
              ),
              const SizedBox(height: 18),
              Text(
                'Trouble signing in? Your school office can unlock your account or send you a new link.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
