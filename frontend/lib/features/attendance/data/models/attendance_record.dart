import 'attendance_status.dart';

/// One historical attendance entry, as returned by the paginated
/// `GET /attendance` history list.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.classSectionId,
    required this.classSectionName,
    required this.studentId,
    required this.studentName,
    required this.attendanceDate,
    required this.status,
    required this.remarks,
    required this.markedByName,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as int,
      classSectionId: json['class_section_id'] as int,
      classSectionName: json['class_section_name'] as String?,
      studentId: json['student_id'] as int,
      studentName: json['student_name'] as String?,
      attendanceDate: json['attendance_date'] as String,
      status: AttendanceStatus.fromApiValue(json['status'] as String),
      remarks: json['remarks'] as String?,
      markedByName: json['marked_by_name'] as String?,
    );
  }

  final int id;
  final int classSectionId;
  final String? classSectionName;
  final int studentId;
  final String? studentName;
  final String attendanceDate;
  final AttendanceStatus status;
  final String? remarks;
  final String? markedByName;
}
