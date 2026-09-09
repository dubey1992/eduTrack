import 'package:flutter/material.dart';

import '../../../marketing/presentation/marketing_colors.dart';

/// The login card's text field styling - a plain [TextFormField] underneath
/// (so widget tests can keep finding it as one, e.g.
/// `find.widgetWithText(TextFormField, 'Email')`) with the marketing
/// palette's border/focus colors instead of the app's internal admin theme,
/// since the login page carries the public-facing identity (see
/// [MarketingColors]).
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
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: MarketingColors.text, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: MarketingColors.subtle),
        floatingLabelStyle: const TextStyle(color: MarketingColors.primary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: MarketingColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MarketingColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MarketingColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MarketingColors.primary, width: 1.5),
        ),
        // The ambient admin theme's error red reads as a washed-out pink
        // against this card's white background - explicit here like every
        // other color on this card, not inherited.
        errorStyle: const TextStyle(color: MarketingColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MarketingColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MarketingColors.danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
