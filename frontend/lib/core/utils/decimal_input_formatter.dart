import 'package:flutter/services.dart';

/// Restricts a money-amount field to digits with at most [decimalPlaces]
/// digits after a single decimal point - matches the `DECIMAL(12,2)` shape
/// every monetary column uses (CLAUDE.md rule 5), so the UI can't accept
/// more precision than the database (and currency) actually supports.
class DecimalTextInputFormatter extends TextInputFormatter {
  DecimalTextInputFormatter({this.decimalPlaces = 2});

  final int decimalPlaces;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final pattern = RegExp(r'^\d*\.?\d{0,' + decimalPlaces.toString() + r'}$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
