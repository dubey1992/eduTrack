import 'date_format.dart';

/// A period to look at a list by: everything, today, this week or this month
/// (docs/teacher-app.md, "Filters by period").
///
/// Weeks run Monday to Sunday, the school week, and months are calendar
/// months. The range is measured from the phone's today, which is the
/// school's today for anybody at the school.
enum DatePeriod {
  all('All'),
  day('Today'),
  week('This week'),
  month('This month');

  const DatePeriod(this.label);

  final String label;

  /// The inclusive range as `yyyy-MM-dd` dates, or null for everything.
  ({String from, String to})? rangeFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    return switch (this) {
      DatePeriod.all => null,
      DatePeriod.day => (from: apiDate(today), to: apiDate(today)),
      DatePeriod.week => (
        from: apiDate(today.subtract(Duration(days: today.weekday - DateTime.monday))),
        to: apiDate(today.add(Duration(days: DateTime.sunday - today.weekday))),
      ),
      // Day 0 of next month is the last day of this one.
      DatePeriod.month => (
        from: apiDate(DateTime(today.year, today.month)),
        to: apiDate(DateTime(today.year, today.month + 1, 0)),
      ),
    };
  }

  /// What an empty list says under this filter.
  String emptyPhrase(String things) => switch (this) {
    DatePeriod.all => 'No $things yet.',
    DatePeriod.day => 'No $things today.',
    DatePeriod.week => 'No $things this week.',
    DatePeriod.month => 'No $things this month.',
  };
}
