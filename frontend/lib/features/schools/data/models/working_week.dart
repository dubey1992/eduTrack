/// The days a school runs (docs/holidays.md).
///
/// Seven flags, **Monday first** — the order the server stores them in, which
/// is `date.weekday()` order. A Sunday-to-Thursday week is therefore
/// `1111001`, which looks odd written down and is the only ordering where the
/// index is the weekday and there is no arithmetic to get wrong.
///
/// This is the shape of the week and nothing else. Holidays are a separate
/// thing: a school closed for Diwali is not a school that does not run on
/// Tuesdays.
class WorkingWeek {
  const WorkingWeek(this._days);

  /// What every school had before the setting existed, and what anything
  /// that does not state a week means.
  const WorkingWeek.mondayToFriday() : _days = const [true, true, true, true, true, false, false];

  /// **Anything unreadable is the Monday-to-Friday week.** The server applies
  /// the same rule to the same column: a week that cannot be read should fall
  /// back to the one the product assumed for its first year, not leave a
  /// screen with no columns and no explanation.
  factory WorkingWeek.fromApiValue(Object? value) {
    if (value is! String || value.length != names.length) return WorkingWeek.mondayToFriday();

    final days = [for (final character in value.split('')) character == '1'];

    if (!days.contains(true) || value.split('').any((c) => c != '0' && c != '1')) {
      return WorkingWeek.mondayToFriday();
    }

    return WorkingWeek(days);
  }

  /// Monday first, matching the stored order.
  static const names = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  static const labels = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// Two letters, for a column header that has to fit.
  static const shortLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  final List<bool> _days;

  String get apiValue => _days.map((on) => on ? '1' : '0').join();

  /// The working days as the API names them, in week order.
  List<String> get dayNames => [
    for (var index = 0; index < names.length; index++)
      if (_days[index]) names[index],
  ];

  /// Their indexes, for a grid that lays out columns.
  List<int> get dayIndexes => [
    for (var index = 0; index < names.length; index++)
      if (_days[index]) index,
  ];

  int get length => _days.where((on) => on).length;

  bool runsOn(int weekdayIndex) => _days[weekdayIndex];

  /// A date's own weekday. `DateTime.monday` is 1, so it is shifted to match
  /// the stored order rather than the other way round.
  bool runsOnDate(DateTime date) => _days[date.weekday - 1];

  WorkingWeek toggled(int index) {
    final days = [..._days];
    days[index] = !days[index];

    return WorkingWeek(days);
  }

  /// A week nobody could keep. The form refuses to save one, and so does the
  /// server: a school that runs no days would refuse every mark on every date
  /// with a message about being closed, which reads exactly like the product
  /// being broken.
  bool get isEmpty => length == 0;

  /// "Monday to Friday", "Sunday to Thursday", or the days listed.
  ///
  /// Named as a range only when the days actually are one, wrapping around
  /// the end of the week - because "Sunday to Thursday" is how the people who
  /// keep that week describe it, and "Monday, Tuesday, Wednesday, Thursday,
  /// Sunday" is the same information in a form nobody uses.
  String get summary {
    if (isEmpty) return 'No days';
    if (length == names.length) return 'Every day';

    final working = dayIndexes;

    for (final start in working) {
      final run = [for (var step = 0; step < length; step++) (start + step) % names.length];

      if (run.toSet().containsAll(working)) {
        return length == 1 ? labels[start] : '${labels[run.first]} to ${labels[run.last]}';
      }
    }

    return working.map((index) => labels[index]).join(', ');
  }

  @override
  bool operator ==(Object other) => other is WorkingWeek && other.apiValue == apiValue;

  @override
  int get hashCode => apiValue.hashCode;
}
