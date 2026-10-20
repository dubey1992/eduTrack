import '../../../schools/data/models/working_week.dart';

/// A day a timetable can have a period on.
///
/// All seven, because the week a school keeps is the school's (see
/// [WorkingWeek] and docs/holidays.md): Sunday to Thursday and six-day weeks
/// are both ordinary. Which of these a particular school's grid shows comes
/// from that school's own week, not from this list.
enum DayOfWeek {
  monday('monday', 'Monday'),
  tuesday('tuesday', 'Tuesday'),
  wednesday('wednesday', 'Wednesday'),
  thursday('thursday', 'Thursday'),
  friday('friday', 'Friday'),
  saturday('saturday', 'Saturday'),
  sunday('sunday', 'Sunday');

  const DayOfWeek(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DayOfWeek fromApiValue(String value) => DayOfWeek.values.firstWhere((d) => d.apiValue == value);

  /// The days one school actually runs, in week order. Monday first, which
  /// is both this enum's order and the order the week is stored in.
  static List<DayOfWeek> of(WorkingWeek week) => [for (final index in week.dayIndexes) DayOfWeek.values[index]];
}
