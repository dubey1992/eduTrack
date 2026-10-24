import 'package:flutter/material.dart';

import 'auth_card.dart';
import 'auth_palette.dart';
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
    this.onAttendantSignIn,
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

  /// Opens the bus attendant's mobile + passcode sign-in. The email form
  /// above refuses an attendant, so they need a way to theirs from here.
  final VoidCallback? onAttendantSignIn;

  @override
  Widget build(BuildContext context) {
    // Every colour on this card comes from the public palette for the
    // phone's current brightness, never from the admin theme and never
    // from a constant - a constant was how a dark phone got a white card
    // with dark boxes in it (see AuthPalette).
    final palette = AuthPalette.of(context);

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
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: palette.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('👋', style: TextStyle(fontSize: 32)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Sign in to continue to School365ai', style: TextStyle(fontSize: 14, color: palette.muted)),
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
                  color: palette.subtle,
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
                          activeColor: palette.primary,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 6),
                        Text('Remember me', style: TextStyle(fontSize: 14, color: palette.text)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onForgotPassword,
                    style: TextButton.styleFrom(foregroundColor: palette.primary),
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
                Icon(Icons.lock_outline, size: 14, color: palette.subtle),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Your data is protected with secure authentication',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: palette.subtle),
                  ),
                ),
              ],
            ),
            if (onAttendantSignIn != null) ...[
              const SizedBox(height: 18),
              Divider(color: palette.border, height: 1),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: onAttendantSignIn,
                  style: TextButton.styleFrom(foregroundColor: palette.primary),
                  icon: const Icon(Icons.directions_bus_filled_outlined, size: 18),
                  label: const Text('Bus attendant? Sign in with your mobile number'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
