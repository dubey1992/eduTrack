import 'package:intl/intl.dart';

/// Formats an amount using the correct symbol/locale for its ISO 4217
/// currency code - never a hardcoded "₹" or "$". See backend CLAUDE.md
/// rule 5 (multi-nation currency model): every amount is paired with the
/// currency it was recorded in, and this is the single place that turns
/// that pair into display text.
String formatCurrency(num amount, String currencyCode) {
  // A space after the code, so "INR 50,000.00" reads the same here as it
  // does on the PDF receipt the school receives.
  return NumberFormat.currency(name: currencyCode, customPattern: '¤ #,##0.00').format(amount);
}
