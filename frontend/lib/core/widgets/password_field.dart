import 'package:flutter/material.dart';

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
      validator: widget.validator ?? (value) => (value == null || value.length < 8) ? 'At least 8 characters' : null,
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
