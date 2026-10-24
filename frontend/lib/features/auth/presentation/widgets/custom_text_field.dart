import 'package:flutter/material.dart';

import 'auth_palette.dart';

/// The login card's text field styling - a plain [TextFormField] underneath
/// (so widget tests can keep finding it as one, e.g.
/// `find.widgetWithText(TextFormField, 'Email')`) with the public palette's
/// border/focus colours instead of the app's internal admin theme, since the
/// login page carries the public-facing identity (see [AuthPalette]).
class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(color: palette.text, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.subtle),
        floatingLabelStyle: TextStyle(color: palette.primary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        // The ambient admin theme's error red reads as a washed-out pink
        // against this card - explicit here like every other colour on it,
        // not inherited.
        errorStyle: TextStyle(color: palette.danger, fontSize: 12, fontWeight: FontWeight.w600),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
