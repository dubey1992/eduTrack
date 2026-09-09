import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_record.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';

class FakeStaffAttendanceRepository implements StaffAttendanceRepository {
  // The field is private but tests (a different library) construct this
  // with a named `register:` argument, so it can't be an initializing
  // formal (`this._register`) - that would make the parameter private too.
  FakeStaffAttendanceRepository({StaffAttendanceRegister? register, this.records = const [], this.failSubmitWith})
    : _register = register; // ignore: prefer_initializing_formals

  StaffAttendanceRegister? _register;
  List<StaffAttendanceRecord> records;
  Failure? failSubmitWith;

  int registerCallCount = 0;
  Map<String, dynamic>? lastSubmitPayload;
  Map<String, dynamic>? lastUpdatePayload;

  @override
  Future<StaffAttendanceRegister> register({int? schoolId, int? departmentId, required String date}) async {
    registerCallCount++;
    return _register!;
  }

  @override
  Future<StaffAttendanceRegister> submit({
    int? schoolId,
    int? departmentId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    if (failSubmitWith != null) throw failSubmitWith!;
    lastSubmitPayload = {
      'school_id': schoolId,
      'department_id': departmentId,
      'attendance_date': attendanceDate,
      'records': records,
    };
    _register = StaffAttendanceRegister(
      schoolId: _register!.schoolId,
      attendanceDate: attendanceDate,
      submitted: true,
      staff: _register!.staff,
    );
    return _register!;
  }

  @override
  Future<StaffAttendanceRegister> update({
    int? schoolId,
    int? departmentId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    lastUpdatePayload = {
      'school_id': schoolId,
      'department_id': departmentId,
      'attendance_date': attendanceDate,
      'records': records,
    };
    _register = StaffAttendanceRegister(
      schoolId: _register!.schoolId,
      attendanceDate: attendanceDate,
      submitted: true,
      staff: _register!.staff,
    );
    return _register!;
  }

  @override
  Future<List<StaffAttendanceRecord>> list({
    int? schoolId,
    int? staffProfileId,
    int? departmentId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    return records;
  }
}
