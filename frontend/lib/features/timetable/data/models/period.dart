/// One period-timing definition for a school (e.g. "Period 1, 08:30-09:15"),
/// configured once and reused across every class section's timetable grid.
class Period {
  const Period({
    required this.id,
    required this.schoolId,
    required this.periodNumber,
    required this.startTime,
    required this.endTime,
  });

  factory Period.fromJson(Map<String, dynamic> json) {
    return Period(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      periodNumber: json['period_number'] as int,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
    );
  }

  final int id;
  final int schoolId;
  final int periodNumber;

  /// HH:mm.
  final String startTime;

  /// HH:mm.
  final String endTime;
}
