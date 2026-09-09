import 'package:edutrack_app/core/utils/decimal_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _valueOf(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group('DecimalTextInputFormatter', () {
    final formatter = DecimalTextInputFormatter();

    test('allows a plain integer', () {
      final result = formatter.formatEditUpdate(_valueOf('100'), _valueOf('1000'));
      expect(result.text, '1000');
    });

    test('allows up to two decimal places', () {
      final result = formatter.formatEditUpdate(_valueOf('25000.0'), _valueOf('25000.00'));
      expect(result.text, '25000.00');
    });

    test('rejects a third decimal digit, keeping the previous value', () {
      final result = formatter.formatEditUpdate(_valueOf('1000.99'), _valueOf('1000.999'));
      expect(result.text, '1000.99');
    });

    test('rejects a non-numeric character', () {
      final result = formatter.formatEditUpdate(_valueOf('100'), _valueOf('100a'));
      expect(result.text, '100');
    });

    test('allows clearing the field', () {
      final result = formatter.formatEditUpdate(_valueOf('100'), _valueOf(''));
      expect(result.text, '');
    });
  });
}
