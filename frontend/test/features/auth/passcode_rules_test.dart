import 'package:edutrack_app/features/auth/data/passcode_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same rules the server applies, so the attendant hears first.
void main() {
  test('accepts an ordinary four-digit passcode', () {
    for (final passcode in ['4827', '1357', '0912', '1123']) {
      expect(passcodeProblem(passcode), isNull, reason: passcode);
    }
  });

  test('must be exactly four digits', () {
    for (final passcode in ['', '482', '48271', '48a7', ' 482']) {
      expect(passcodeProblem(passcode), 'The passcode must be exactly 4 digits.', reason: passcode);
    }
  });

  test('may not be one digit repeated', () {
    expect(passcodeProblem('0000'), 'Choose a passcode that is not one digit repeated.');
    expect(passcodeProblem('7777'), 'Choose a passcode that is not one digit repeated.');
  });

  test('may not be a straight run up or down', () {
    for (final passcode in ['1234', '6789', '4321', '9876', '0123']) {
      expect(passcodeProblem(passcode), 'Choose a passcode that is not a straight run like 1234.', reason: passcode);
    }
  });

  test('a run that turns back is fine', () {
    expect(passcodeProblem('1232'), isNull);
    expect(passcodeProblem('2468'), isNull);
  });
}
