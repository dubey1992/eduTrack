import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../../my_teaching/application/staff_outbox.dart';
import '../../my_teaching/data/outbox.dart';

import '../../../core/errors/failure.dart';

import '../data/models/check_in_event.dart';
import '../data/models/staff_attendance_register.dart';
import '../data/models/staff_attendance_status.dart';
import '../data/staff_attendance_repository.dart';

class StaffAttendanceRegisterParams {
  const StaffAttendanceRegisterParams({this.schoolId, this.departmentId, required this.date});

  /// Required for a SUPER_ADMIN; ignored/derived server-side for every
  /// other role (see StaffAttendanceController::resolveSchool).
  final int? schoolId;

  /// Optional filter - an HOD's roster is narrowed to their own
  /// department(s) server-side regardless of this value.
  final int? departmentId;

  /// yyyy-MM-dd.
  final String date;

  @override
  bool operator ==(Object other) =>
      other is StaffAttendanceRegisterParams &&
      other.schoolId == schoolId &&
      other.departmentId == departmentId &&
      other.date == date;

  @override
  int get hashCode => Object.hash(schoolId, departmentId, date);
}

/// The day's check-ins and check-outs from the app, for the same school,
/// department and date as the register beside them.
final staffCheckInLogProvider = FutureProvider.autoDispose.family<List<CheckInEvent>, StaffAttendanceRegisterParams>(
  (ref, params) => ref
      .read(staffAttendanceRepositoryProvider)
      .checkIns(schoolId: params.schoolId, departmentId: params.departmentId, date: params.date),
  retry: (retryCount, error) => null,
);

final staffAttendanceRegisterProvider = AsyncNotifierProvider.autoDispose
    .family<StaffAttendanceRegisterNotifier, StaffAttendanceRegister, StaffAttendanceRegisterParams>(
      StaffAttendanceRegisterNotifier.new,
    );

/// Holds one school's (optionally department-filtered) staff register for
/// one day - the roster plus whatever's been marked locally, up until it's
/// submitted/updated. The family argument is a constructor field here
/// (Riverpod 3's family notifiers don't receive it through `build()`), not
/// an override parameter.
class StaffAttendanceRegisterNotifier extends AsyncNotifier<StaffAttendanceRegister> {
  StaffAttendanceRegisterNotifier(this.params);

  final StaffAttendanceRegisterParams params;

  @override
  Future<StaffAttendanceRegister> build() {
    return ref
        .read(staffAttendanceRepositoryProvider)
        .register(schoolId: params.schoolId, departmentId: params.departmentId, date: params.date);
  }

  void setStatus(int staffProfileId, StaffAttendanceStatus status) {
    _updateEntry(staffProfileId, (entry) => entry.copyWith(status: status));
  }

  void setCheckIn(int staffProfileId, String? time) {
    _updateEntry(staffProfileId, (entry) => entry.copyWith(checkIn: time, clearCheckIn: time == null));
  }

  void setCheckOut(int staffProfileId, String? time) {
    _updateEntry(staffProfileId, (entry) => entry.copyWith(checkOut: time, clearCheckOut: time == null));
  }

  void setRemarks(int staffProfileId, String? remarks) {
    _updateEntry(staffProfileId, (entry) => entry.copyWith(remarks: remarks));
  }

  void markAllPresent() {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(_withStaff(current, (entry) => entry.copyWith(status: StaffAttendanceStatus.present)));
  }

  void _updateEntry(int staffProfileId, StaffRosterEntry Function(StaffRosterEntry) transform) {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      _withStaff(current, (entry) => entry.staffProfileId == staffProfileId ? transform(entry) : entry),
    );
  }

  StaffAttendanceRegister _withStaff(
    StaffAttendanceRegister current,
    StaffRosterEntry Function(StaffRosterEntry) transform,
  ) {
    return StaffAttendanceRegister(
      schoolId: current.schoolId,
      attendanceDate: current.attendanceDate,
      submitted: current.submitted,
      staff: [for (final entry in current.staff) transform(entry)],
    );
  }

  /// True once every roster entry has a status - the Submit/Update button
  /// stays disabled until then, matching Student Attendance's expectation
  /// that a day is submitted for the whole roster at once.
  bool get isComplete => state.value?.staff.every((s) => s.status != null) ?? false;

  /// [confirmLeave] marks present somebody who is on leave that day, once
  /// the office has been asked (the server answers STAFF_ON_LEAVE first).
  ///
  /// True when there was no connection and the web app kept the register to
  /// send later (docs/offline-web.md, O3); false once the server has it.
  Future<bool> submitOrUpdate({bool confirmLeave = false}) async {
    final current = state.value;
    if (current == null || !isComplete) return false;

    final records = [
      for (final entry in current.staff)
        {
          'staff_profile_id': entry.staffProfileId,
          'status': entry.status!.apiValue,
          if (entry.checkIn != null) 'check_in': entry.checkIn,
          if (entry.checkOut != null) 'check_out': entry.checkOut,
          if (entry.remarks != null && entry.remarks!.isNotEmpty) 'remarks': entry.remarks,
        },
    ];

    final repository = ref.read(staffAttendanceRepositoryProvider);
    try {
      final result = current.submitted
          ? await repository.update(
              schoolId: params.schoolId,
              departmentId: params.departmentId,
              attendanceDate: current.attendanceDate,
              records: records,
              confirmLeave: confirmLeave,
            )
          : await repository.submit(
              schoolId: params.schoolId,
              departmentId: params.departmentId,
              attendanceDate: current.attendanceDate,
              records: records,
              confirmLeave: confirmLeave,
            );
      state = AsyncData(result);
      return false;
    } on Failure catch (failure) {
      // A new register is kept and sent when the line is back; changing one
      // already submitted needs the server.
      if (failure.code != 'NETWORK_ERROR' || current.submitted) rethrow;
      final kept = await ref
          .read(staffOutboxProvider.notifier)
          .keepFromWeb(
            kind: OutboxKind.staffRegister,
            key: OutboxItem.staffRegisterKey(params.departmentId, current.attendanceDate),
            label: 'Staff register, ${formatIsoDate(current.attendanceDate)}',
            payload: {
              'school_id': params.schoolId,
              'department_id': params.departmentId,
              'attendance_date': current.attendanceDate,
              'records': records,
              'confirm_leave': confirmLeave,
            },
          );
      if (!kept) rethrow;
      return true;
    }
  }
}
