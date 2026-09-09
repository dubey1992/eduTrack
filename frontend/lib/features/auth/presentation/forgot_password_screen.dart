import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../marketing/presentation/marketing_colors.dart';
import '../data/auth_repository.dart';
import 'widgets/auth_card.dart';
import 'widgets/custom_text_field.dart';
import 'widgets/primary_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).forgotPassword(_emailController.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarketingColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AuthCard(child: _sent ? _buildSentMessage() : _buildForm()),
          ),
        ),
      ),
    );
  }

  Widget _buildSentMessage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 40, color: MarketingColors.primary),
        const SizedBox(height: 16),
        const Text(
          'Check your email',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        const SizedBox(height: 8),
        const Text(
          'If an account exists for that email, a password reset link has been sent.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: MarketingColors.muted),
        ),
        const SizedBox(height: 22),
        const _BackToLoginButton(),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Forgot Password?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: MarketingColors.text),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter your email and we will send you a password reset link.',
            style: TextStyle(fontSize: 14, color: MarketingColors.muted),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: MarketingColors.danger)),
            const SizedBox(height: 12),
          ],
          CustomTextField(
            controller: _emailController,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            validator: (value) => (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
            onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: 'Send Reset Link', isLoading: _isSubmitting, onPressed: _submit),
          const SizedBox(height: 16),
          const _BackToLoginButton(),
        ],
      ),
    );
  }
}

class _BackToLoginButton extends StatelessWidget {
  const _BackToLoginButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => context.go('/login'),
        style: TextButton.styleFrom(foregroundColor: MarketingColors.primary),
        icon: const Icon(Icons.arrow_back, size: 16),
        label: const Text('Back to Login'),
      ),
    );
  }
}
