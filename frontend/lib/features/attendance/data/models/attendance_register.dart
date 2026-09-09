import '../../../holidays/data/models/holiday.dart';
import 'attendance_status.dart';

/// One student's row in a class's daily register - [status]/[remarks] are
/// null until the day has been marked.
class AttendanceRosterEntry {
  const AttendanceRosterEntry({
    required this.studentId,
    required this.name,
    required this.rollNumber,
    required this.status,
    required this.remarks,
  });

  factory AttendanceRosterEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceRosterEntry(
      studentId: json['student_id'] as int,
      name: json['name'] as String,
      rollNumber: json['roll_number'] as String?,
      status: json['status'] == null ? null : AttendanceStatus.fromApiValue(json['status'] as String),
      remarks: json['remarks'] as String?,
    );
  }

  final int studentId;
  final String name;
  final String? rollNumber;
  final AttendanceStatus? status;
  final String? remarks;

  AttendanceRosterEntry copyWith({AttendanceStatus? status, String? remarks}) {
    return AttendanceRosterEntry(
      studentId: studentId,
      name: name,
      rollNumber: rollNumber,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
    );
  }
}

/// A class section's attendance for one day - the active roster, each
/// paired with its mark (or none if [submitted] is false). [holiday] is set
/// when the day is on the school's calendar; the server refuses to mark it.
class AttendanceRegister {
  const AttendanceRegister({
    required this.classSectionId,
    required this.attendanceDate,
    required this.submitted,
    required this.students,
    this.holiday,
  });

  factory AttendanceRegister.fromJson(Map<String, dynamic> json) {
    return AttendanceRegister(
      classSectionId: json['class_section_id'] as int,
      attendanceDate: json['attendance_date'] as String,
      submitted: json['submitted'] as bool,
      students: (json['students'] as List).cast<Map<String, dynamic>>().map(AttendanceRosterEntry.fromJson).toList(),
      holiday: json['holiday'] == null ? null : HolidaySummary.fromJson(json['holiday'] as Map<String, dynamic>),
    );
  }

  final int classSectionId;
  final String attendanceDate;
  final bool submitted;
  final List<AttendanceRosterEntry> students;
  final HolidaySummary? holiday;
}
