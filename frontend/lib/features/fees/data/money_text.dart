/// Money as typed and as sent, in whole cents - never a double, so that
/// "do the installments add up to the fee" is exact (docs/fees.md).
library;

final _amount = RegExp(r'^\d{1,10}(\.\d{1,2})?$');

/// "1200.5" -> 120050. Null for anything that is not an amount with at most
/// two decimal places.
int? centsOf(String text) {
  final value = text.trim();
  if (!_amount.hasMatch(value)) return null;

  final parts = value.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;

  return whole * 100 + fraction;
}

/// 120050 -> "1200.50", the way the server writes amounts.
String textOfCents(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
