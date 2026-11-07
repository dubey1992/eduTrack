/// Why a new passcode will not do, or null - the same three rules the
/// server applies (school/attendants.py and school/family.py
/// `passcode_problem`), checked here first so the person hears about them
/// before a round trip. A bus attendant's passcode is 4 digits, a parent's 6.
String? passcodeProblem(String passcode, {int length = 4}) {
  if (!RegExp('^[0-9]{$length}\$').hasMatch(passcode)) return 'The passcode must be exactly $length digits.';

  if (passcode.split('').toSet().length == 1) return 'Choose a passcode that is not one digit repeated.';

  final digits = passcode.split('').map(int.parse).toList();
  final steps = {for (var i = 1; i < digits.length; i++) digits[i] - digits[i - 1]};
  if (steps.length == 1 && (steps.first == 1 || steps.first == -1)) {
    return 'Choose a passcode that is not a straight run like ${length == 4 ? '1234' : '123456'}.';
  }

  return null;
}
