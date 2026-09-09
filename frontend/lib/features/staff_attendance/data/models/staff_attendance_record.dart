import 'staff_attendance_status.dart';

/// One historical attendance entry, as returned by the paginated
/// `GET /staff-attendance` history list.
class StaffAttendanceRecord {
  const StaffAttendanceRecord({
    required this.id,
    required this.staffProfileId,
    required this.employeeId,
    required this.staffName,
    required this.departmentName,
    required this.attendanceDate,
    required this.status,
    required this.checkIn,
    required this.checkOut,
    required this.workingHours,
    required this.remarks,
    required this.markedByName,
  });

  factory StaffAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return StaffAttendanceRecord(
      id: json['id'] as int,
      staffProfileId: json['staff_profile_id'] as int,
      employeeId: json['employee_id'] as String?,
      staffName: json['staff_name'] as String?,
      departmentName: json['department_name'] as String?,
      attendanceDate: json['attendance_date'] as String,
      status: StaffAttendanceStatus.fromApiValue(json['status'] as String),
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      workingHours: json['working_hours'] as String?,
      remarks: json['remarks'] as String?,
      markedByName: json['marked_by_name'] as String?,
    );
  }

  final int id;
  final int staffProfileId;
  final String? employeeId;
  final String? staffName;
  final String? departmentName;
  final String attendanceDate;
  final StaffAttendanceStatus status;
  final String? checkIn;
  final String? checkOut;
  final String? workingHours;
  final String? remarks;
  final String? markedByName;
}
