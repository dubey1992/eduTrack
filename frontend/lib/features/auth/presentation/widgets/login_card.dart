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
      child: AutofillGroup(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Centred when the page stretches the card to the height of
            // what sits beside it.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Says what this is and which account it wants, rather than
              // welcoming someone back on their first day (2026-11-06).
              Text(
                'Sign in to School365ai',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: palette.text),
              ),
              const SizedBox(height: 6),
              Text(
                'Use the email and password your school set up for you.',
                style: TextStyle(fontSize: 14, height: 1.4, color: palette.muted),
              ),
              const SizedBox(height: 24),
              CustomTextField(
                controller: emailController,
                label: 'Email',
                prefixIcon: Icons.mail_outline,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                textInputAction: TextInputAction.next,
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
                prefixIcon: Icons.lock_outline,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
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
                Row(
                  children: [
                    Expanded(child: Divider(color: palette.border, height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(fontSize: 13, color: palette.subtle)),
                    ),
                    Expanded(child: Divider(color: palette.border, height: 1)),
                  ],
                ),
                const SizedBox(height: 14),
                // A real button, not a small link: an attendant who types their
                // mobile number into Email above only gets an error.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onAttendantSignIn,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.primary,
                      side: BorderSide(color: palette.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.directions_bus_filled_outlined, size: 18),
                    label: const Text('Bus attendant? Sign in with your mobile number', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
