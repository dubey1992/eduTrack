/// The days a school runs (docs/holidays.md).
///
/// Seven characters, **Monday first** — the order the server stores them in,
/// which is `date.weekday()` order. A Sunday-to-Thursday week is therefore
/// `1111001`, which looks odd written down and is the only ordering where the
/// index is the weekday and there is no arithmetic to get wrong.
///
/// Each one is a day: `'0'` closed, `'1'` a full day, `'2'` a half day.
///
/// **A half day is a full working day.** It is a shorter day, not a fraction
/// of one — what the shape decides is which periods the day has, and nothing
/// that counts working days cares which shape they were.
///
/// This is the shape of the week and nothing else. Holidays are a separate
/// thing: a school closed for Diwali is not a school that does not run on
/// Tuesdays.
class WorkingWeek {
  const WorkingWeek(this._days);

  /// What every school had before the setting existed, and what anything
  /// that does not state a week means.
  const WorkingWeek.mondayToFriday() : _days = const ['1', '1', '1', '1', '1', '0', '0'];

  static const closed = '0';
  static const full = '1';
  static const half = '2';

  /// What a period belongs to. Matches the server's `periods.day_shape`.
  static const fullDay = 'full';
  static const halfDay = 'half';

  /// **Anything unreadable is the Monday-to-Friday week.** The server applies
  /// the same rule to the same column: a week that cannot be read should fall
  /// back to the one the product assumed for its first year, not leave a
  /// screen with no columns and no explanation.
  factory WorkingWeek.fromApiValue(Object? value) {
    if (value is! String || value.length != names.length) return WorkingWeek.mondayToFriday();

    final days = value.split('');

    if (days.any((day) => day != closed && day != full && day != half) || !days.any((day) => day != closed)) {
      return WorkingWeek.mondayToFriday();
    }

    return WorkingWeek(days);
  }

  /// Monday first, matching the stored order.
  static const names = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  static const labels = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// Two letters, for a column header that has to fit.
  static const shortLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  final List<String> _days;

  String get apiValue => _days.join();

  /// The working days as the API names them, in week order.
  List<String> get dayNames => [
    for (var index = 0; index < names.length; index++)
      if (_days[index] != closed) names[index],
  ];

  /// Their indexes, for a grid that lays out columns.
  List<int> get dayIndexes => [
    for (var index = 0; index < names.length; index++)
      if (_days[index] != closed) index,
  ];

  int get length => _days.where((day) => day != closed).length;

  bool runsOn(int weekdayIndex) => _days[weekdayIndex] != closed;

  /// `full`, `half`, or null on a day this school does not run.
  String? shapeOf(int weekdayIndex) => switch (_days[weekdayIndex]) {
    full => fullDay,
    half => halfDay,
    _ => null,
  };

  bool isHalfDay(int weekdayIndex) => _days[weekdayIndex] == half;

  /// Whether this school has any half day at all. What decides whether
  /// a screen needs to mention the distinction.
  bool get hasHalfDay => _days.contains(half);

  /// A date's own weekday. `DateTime.monday` is 1, so it is shifted to match
  /// the stored order rather than the other way round.
  bool runsOnDate(DateTime date) => runsOn(date.weekday - 1);

  String? shapeOnDate(DateTime date) => shapeOf(date.weekday - 1);

  /// On or off. **A day that was a half day comes back as a full one**, which
  /// is why the field marks half days plainly: turning one off and on again
  /// is a change somebody should be able to see they made.
  WorkingWeek toggled(int index) {
    final days = [..._days];
    days[index] = days[index] == closed ? full : closed;

    return WorkingWeek(days);
  }

  /// Sets a day's shape without disturbing the rest. Used by the editor that
  /// can choose between them.
  WorkingWeek withShape(int index, String shape) {
    final days = [..._days];
    days[index] = shape == halfDay ? half : full;

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

  /// "Saturday is a half day", or nothing when every day is a full one.
  ///
  /// Said separately from [summary], because a range like "Monday to
  /// Saturday" is true and still hides the part somebody most needs to check.
  String? get halfDayNote {
    final shorter = [
      for (var index = 0; index < names.length; index++)
        if (isHalfDay(index)) labels[index],
    ];

    if (shorter.isEmpty) return null;

    return shorter.length == 1 ? '${shorter.single} is a half day.' : '${shorter.join(', ')} are half days.';
  }

  @override
  bool operator ==(Object other) => other is WorkingWeek && other.apiValue == apiValue;

  @override
  int get hashCode => apiValue.hashCode;
}
