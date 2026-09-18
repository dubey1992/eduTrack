import 'package:flutter/material.dart';

import '../../../marketing/presentation/marketing_colors.dart';
import 'auth_card.dart';
import 'custom_text_field.dart';
import 'primary_button.dart';

/// The login form itself, matching the prototype's `.card`. Pure
/// presentation - every field's value, validator, and the submit action are
/// handed in by [LoginScreen], which is the only widget in this feature that
/// talks to `authNotifierProvider`. Keeping this widget free of `ref` is
/// what makes "no auth logic inside widgets" actually true rather than just
/// a convention by habit.
class LoginCard extends StatelessWidget {
  const LoginCard({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscurePassword;
  final bool rememberMe;
  final ValueChanged<bool> onRememberMeChanged;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Welcome Back',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: MarketingColors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('👋', style: TextStyle(fontSize: 32)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Sign in to continue to School365ai',
              style: TextStyle(fontSize: 14, color: MarketingColors.muted),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              controller: emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Email is required';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 14),
            CustomTextField(
              controller: passwordController,
              label: 'Password',
              obscureText: obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: MarketingColors.subtle,
                ),
                tooltip: obscurePassword ? 'Show password' : 'Hide password',
                onPressed: onToggleObscurePassword,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Password is required';
                return null;
              },
              onFieldSubmitted: (_) => isSubmitting ? null : onSubmit(),
            ),
            const SizedBox(height: 12),
            // A Wrap, not a Row: on a narrow phone the two controls cannot
            // share a line, and a Row squeezed "Remember me" until it broke
            // mid-word ("Remem / ber me"). Here the link drops to its own
            // line instead. Full width, so spaceBetween has room to put the
            // link at the far edge rather than beside the checkbox.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 4,
                children: [
                  InkWell(
                    onTap: () => onRememberMeChanged(!rememberMe),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: rememberMe,
                          onChanged: (value) => onRememberMeChanged(value ?? false),
                          // Explicit colors throughout, same as every other
                          // control here - this card intentionally carries the
                          // marketing palette regardless of the device's
                          // light/dark setting (see MarketingColors), so
                          // nothing here can fall back to the admin app's
                          // ambient theme.
                          activeColor: MarketingColors.primary,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 6),
                        const Text('Remember me', style: TextStyle(fontSize: 14, color: MarketingColors.text)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onForgotPassword,
                    style: TextButton.styleFrom(foregroundColor: MarketingColors.primary),
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(label: 'Sign In', isLoading: isSubmitting, onPressed: onSubmit),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 14, color: MarketingColors.subtle),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Your data is protected with secure authentication',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: MarketingColors.subtle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
