import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_status.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_type.dart';
import 'package:edutrack_app/features/staff_leave/data/models/staff_leave.dart';
import 'package:edutrack_app/features/staff_leave/data/models/staff_leave_summary.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';

class FakeStaffLeaveRepository implements StaffLeaveRepository {
  FakeStaffLeaveRepository({
    this.leaves = const [],
    this.summaryData = const StaffLeaveSummary(pending: 0, approvedThisMonth: 0, rejected: 0, onLeaveToday: 0),
    this.failApplyWith,
    this.failReviewWith,
    this.applyResultStatus = LeaveStatus.pending,
  });

  List<StaffLeave> leaves;
  StaffLeaveSummary summaryData;
  Failure? failApplyWith;
  Failure? failReviewWith;

  /// The status `apply()` returns the newly-created leave with - lets a
  /// test simulate a School Admin's auto-approved application (see
  /// StaffLeaveService::apply() on the backend) without a real backend.
  LeaveStatus applyResultStatus;

  Map<String, dynamic>? lastApplyPayload;
  int? lastApprovedId;
  int? lastRejectedId;

  @override
  Future<StaffLeave> apply({
    required LeaveType leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    if (failApplyWith != null) throw failApplyWith!;
    lastApplyPayload = {
      'leave_type': leaveType.apiValue,
      'start_date': startDate,
      'end_date': endDate,
      'reason': reason,
    };
    final created = StaffLeave(
      id: leaves.length + 1,
      schoolId: 1,
      staffProfileId: 1,
      employeeId: 'EMP-001',
      staffName: 'Test Staff',
      departmentName: 'Mathematics',
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      status: applyResultStatus,
      appliedByName: 'Test Staff',
      reviewedByName: applyResultStatus == LeaveStatus.pending ? null : 'Test Staff',
      reviewRemarks: applyResultStatus == LeaveStatus.pending
          ? null
          : 'Auto-approved - School Admin is the head of the school.',
    );
    leaves = [...leaves, created];
    return created;
  }

  @override
  Future<PaginatedResponse<StaffLeave>> list({
    int? schoolId,
    int? departmentId,
    String? status,
    required int page,
    required int perPage,
  }) async {
    return PaginatedResponse(items: leaves, currentPage: page, lastPage: 1, total: leaves.length, perPage: perPage);
  }

  @override
  Future<StaffLeaveSummary> summary({int? schoolId}) async => summaryData;

  @override
  Future<StaffLeave> approve(int leaveId, {String? remarks}) async {
    if (failReviewWith != null) throw failReviewWith!;
    lastApprovedId = leaveId;
    return _reviewed(leaveId, LeaveStatus.approved, remarks);
  }

  @override
  Future<StaffLeave> reject(int leaveId, {String? remarks}) async {
    if (failReviewWith != null) throw failReviewWith!;
    lastRejectedId = leaveId;
    return _reviewed(leaveId, LeaveStatus.rejected, remarks);
  }

  StaffLeave _reviewed(int leaveId, LeaveStatus status, String? remarks) {
    final existing = leaves.firstWhere((l) => l.id == leaveId);
    final updated = StaffLeave(
      id: existing.id,
      schoolId: existing.schoolId,
      staffProfileId: existing.staffProfileId,
      employeeId: existing.employeeId,
      staffName: existing.staffName,
      departmentName: existing.departmentName,
      leaveType: existing.leaveType,
      startDate: existing.startDate,
      endDate: existing.endDate,
      reason: existing.reason,
      status: status,
      appliedByName: existing.appliedByName,
      reviewedByName: 'Reviewer',
      reviewRemarks: remarks,
    );
    leaves = [for (final l in leaves) l.id == leaveId ? updated : l];
    return updated;
  }
}
