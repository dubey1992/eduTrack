import 'package:flutter/material.dart';

/// The rule for a password being chosen, as the API applies it (Phase 21):
/// at least 8 characters, with a letter and a number. The API also refuses
/// common passwords, which it says so itself - that list is not shipped here.
String? newPasswordProblem(String? value) {
  if (value == null || value.length < 8) return 'At least 8 characters';
  if (!RegExp('[A-Za-z]').hasMatch(value) || !RegExp('[0-9]').hasMatch(value)) {
    return 'Use at least one letter and one number';
  }
  return null;
}

/// What every new-password field says under itself.
const newPasswordHint = 'At least 8 characters, with a letter and a number.';

/// A password field with a reveal toggle.
///
/// Hidden by default, because a password typed in an office is typed in front
/// of whoever is standing there; revealable, because the alternative is people
/// mistyping a password they cannot see and being locked out. Every password
/// field in the app uses this, so the behaviour and the icon are the same
/// wherever one appears.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.helperText,
    this.textInputAction,
    this.onFieldSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      // Without a validator of its own, a field is one where a password is
      // being chosen.
      validator: widget.validator ?? newPasswordProblem,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        suffixIcon: IconButton(
          // The tooltip says what the button will do, not what the field is -
          // the icon alone is ambiguous to anyone who has not met it before.
          tooltip: _obscured ? 'Show password' : 'Hide password',
          icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
