import '../../../schools/data/models/working_week.dart';
import 'day_of_week.dart';

/// One occupied cell in a class section's weekly grid - a subject taught by
/// a teacher, in one period, on one day.
class TimetableEntry {
  const TimetableEntry({
    required this.id,
    required this.schoolId,
    required this.classSectionId,
    required this.classSectionName,
    required this.periodId,
    required this.periodNumber,
    required this.dayOfWeek,
    this.periodDayShape = WorkingWeek.fullDay,
    required this.subjectId,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> json) {
    return TimetableEntry(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      classSectionId: json['class_section_id'] as int,
      classSectionName: json['class_section_name'] as String?,
      periodId: json['period_id'] as int,
      periodNumber: json['period_number'] as int?,
      dayOfWeek: DayOfWeek.fromApiValue(json['day_of_week'] as String),
      periodDayShape: json['period_day_shape'] as String? ?? WorkingWeek.fullDay,
      subjectId: json['subject_id'] as int,
      subjectName: json['subject_name'] as String?,
      teacherId: json['teacher_id'] as int,
      teacherName: json['teacher_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final int classSectionId;
  final String? classSectionName;
  final int periodId;
  final int? periodNumber;
  final DayOfWeek dayOfWeek;

  /// Which shape of day this cell's period belongs to. The teacher's own
  /// schedule is drawn from entries alone - it never loads the school's
  /// periods - so without this a half day's period would be laid out
  /// among the full day's and land under a column that is not there.
  final String periodDayShape;
  final int subjectId;
  final String? subjectName;
  final int teacherId;
  final String? teacherName;
}
