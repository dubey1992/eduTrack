import 'leave_status.dart';
import 'leave_type.dart';

/// One leave request, as returned by `POST /leaves`, `GET /leaves`, and the
/// approve/reject endpoints.
class StaffLeave {
  const StaffLeave({
    required this.id,
    required this.schoolId,
    required this.staffProfileId,
    required this.employeeId,
    required this.staffName,
    required this.departmentName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.appliedByName,
    required this.reviewedByName,
    required this.reviewRemarks,
  });

  factory StaffLeave.fromJson(Map<String, dynamic> json) {
    return StaffLeave(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      staffProfileId: json['staff_profile_id'] as int,
      employeeId: json['employee_id'] as String?,
      staffName: json['staff_name'] as String?,
      departmentName: json['department_name'] as String?,
      leaveType: LeaveType.fromApiValue(json['leave_type'] as String),
      startDate: json['start_date'] as String,
      endDate: json['end_date'] as String,
      reason: json['reason'] as String,
      status: LeaveStatus.fromApiValue(json['status'] as String),
      appliedByName: json['applied_by_name'] as String?,
      reviewedByName: json['reviewed_by_name'] as String?,
      reviewRemarks: json['review_remarks'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final int staffProfileId;
  final String? employeeId;
  final String? staffName;
  final String? departmentName;
  final LeaveType leaveType;

  /// yyyy-MM-dd.
  final String startDate;

  /// yyyy-MM-dd.
  final String endDate;
  final String reason;
  final LeaveStatus status;
  final String? appliedByName;
  final String? reviewedByName;
  final String? reviewRemarks;
}
