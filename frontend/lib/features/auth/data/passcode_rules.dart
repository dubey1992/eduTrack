/// Why a new passcode will not do, or null - the same three rules the
/// server applies (backend school/attendants.py `passcode_problem`), checked
/// here first so the attendant hears about them before a round trip.
String? passcodeProblem(String passcode) {
  if (!RegExp(r'^\d{4}$').hasMatch(passcode)) return 'The passcode must be exactly 4 digits.';

  if (passcode.split('').toSet().length == 1) return 'Choose a passcode that is not one digit repeated.';

  final digits = passcode.split('').map(int.parse).toList();
  final steps = {for (var i = 1; i < digits.length; i++) digits[i] - digits[i - 1]};
  if (steps.length == 1 && (steps.first == 1 || steps.first == -1)) {
    return 'Choose a passcode that is not a straight run like 1234.';
  }

  return null;
}
