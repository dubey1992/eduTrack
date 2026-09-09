import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_record.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';

class FakeAttendanceRepository implements AttendanceRepository {
  // The field is private but tests (a different library) construct this
  // with a named `register:` argument, so it can't be an initializing
  // formal (`this._register`) - that would make the parameter private too.
  FakeAttendanceRepository({
    AttendanceRegister? register,
    this.records = const [],
    this.failSubmitWith,
    this.failRegisterWith,
  }) : _register = register; // ignore: prefer_initializing_formals

  AttendanceRegister? _register;
  List<AttendanceRecord> records;
  Failure? failSubmitWith;
  Failure? failRegisterWith;

  int registerCallCount = 0;
  Map<String, dynamic>? lastSubmitPayload;
  Map<String, dynamic>? lastUpdatePayload;

  @override
  Future<AttendanceRegister> register({required int classSectionId, required String date}) async {
    registerCallCount++;
    if (failRegisterWith != null) throw failRegisterWith!;
    return _register!;
  }

  @override
  Future<AttendanceRegister> submit({
    required int classSectionId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    if (failSubmitWith != null) throw failSubmitWith!;
    lastSubmitPayload = {'class_section_id': classSectionId, 'attendance_date': attendanceDate, 'records': records};
    _register = AttendanceRegister(
      classSectionId: classSectionId,
      attendanceDate: attendanceDate,
      submitted: true,
      students: _register!.students,
    );
    return _register!;
  }

  @override
  Future<AttendanceRegister> update({
    required int classSectionId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    lastUpdatePayload = {'class_section_id': classSectionId, 'attendance_date': attendanceDate, 'records': records};
    _register = AttendanceRegister(
      classSectionId: classSectionId,
      attendanceDate: attendanceDate,
      submitted: true,
      students: _register!.students,
    );
    return _register!;
  }

  @override
  Future<List<AttendanceRecord>> list({
    int? schoolId,
    int? classSectionId,
    int? studentId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    return records;
  }
}
