import '../../../schools/data/models/working_week.dart';

/// One period-timing definition for a school (e.g. "Period 1, 08:30-09:15"),
/// configured once and reused across every class section's timetable grid.
class Period {
  const Period({
    required this.id,
    required this.schoolId,
    required this.periodNumber,
    this.dayShape = WorkingWeek.fullDay,
    required this.startTime,
    required this.endTime,
  });

  factory Period.fromJson(Map<String, dynamic> json) {
    return Period(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      periodNumber: json['period_number'] as int,
      // `full` when the server does not say, which is every period that
      // existed before half days did.
      dayShape: json['day_shape'] as String? ?? WorkingWeek.fullDay,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
    );
  }

  final int id;
  final int schoolId;
  final int periodNumber;

  /// Which shape of day these bells belong to - `full` or `half`. A school
  /// that runs a Saturday morning rings shorter ones on it, and fewer
  /// (docs/holidays.md).
  final String dayShape;

  bool get isHalfDay => dayShape == WorkingWeek.halfDay;

  /// HH:mm.
  final String startTime;

  /// HH:mm.
  final String endTime;
}
