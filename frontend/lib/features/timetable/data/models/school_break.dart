import '../../../schools/data/models/working_week.dart';

/// A break in the school day - lunch, a short break - shown in its place in
/// the timetable. Never a period: it is not numbered and holds no class.
class SchoolBreak {
  const SchoolBreak({
    required this.id,
    required this.schoolId,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.dayShape = WorkingWeek.fullDay,
  });

  factory SchoolBreak.fromJson(Map<String, dynamic> json) {
    return SchoolBreak(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      name: json['name'] as String,
      dayShape: json['day_shape'] as String? ?? WorkingWeek.fullDay,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
    );
  }

  final int id;
  final int schoolId;
  final String name;

  /// `full` or `half`, like periods.
  final String dayShape;

  /// HH:mm.
  final String startTime;

  /// HH:mm.
  final String endTime;
}
