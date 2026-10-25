import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/check_in/data/models/my_attendance_day.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_status.dart';

/// The staff register's own-day endpoints, in memory. Checking in and out
/// move the day along the way the server does; [refuseWith] stands in for a
/// refusal (too far, already in).
class FakeCheckInRepository implements CheckInRepository {
  FakeCheckInRepository({MyAttendanceDay? day, this.refuseWith, this.failLoadWith}) : day = day ?? notCheckedIn();

  MyAttendanceDay day;
  Failure? refuseWith;
  Failure? failLoadWith;

  /// Where the phone said it was, on the last check-in or check-out.
  DevicePosition? sentFrom;
  int loads = 0;

  /// If set, checkIn() waits for it - to hold a request in flight.
  Completer<void>? checkInGate;
  int checkIns = 0;

  @override
  Future<MyAttendanceDay> today() async {
    loads++;
    if (failLoadWith != null) throw failLoadWith!;
    return day;
  }

  @override
  Future<MyAttendanceDay> checkIn(DevicePosition at) async {
    checkIns++;
    sentFrom = at;
    if (checkInGate != null) await checkInGate!.future;
    if (refuseWith != null) throw refuseWith!;
    return day = attendanceDay(status: StaffAttendanceStatus.present, checkIn: '09:05', late: true);
  }

  @override
  Future<MyAttendanceDay> checkOut(DevicePosition at) async {
    sentFrom = at;
    if (refuseWith != null) throw refuseWith!;
    return day = attendanceDay(
      status: StaffAttendanceStatus.present,
      checkIn: '09:05',
      checkOut: '16:05',
      workingHours: '7h 0m',
      late: true,
    );
  }
}

MyAttendanceDay notCheckedIn() => attendanceDay();

MyAttendanceDay attendanceDay({
  bool enabled = true,
  bool isOpen = true,
  bool onLeave = false,
  StaffAttendanceStatus? status,
  String? checkIn,
  String? checkOut,
  bool late = false,
  String? workingHours,
  bool markedBySomeoneElse = false,
  String? blockedReason,
}) {
  final open = enabled && isOpen && !onLeave && blockedReason == null;

  return MyAttendanceDay(
    date: DateTime(2026, 10, 26),
    enabled: enabled,
    radiusMetres: 100,
    isOpen: isOpen,
    onLeave: onLeave,
    status: status,
    checkIn: checkIn,
    checkOut: checkOut,
    late: late,
    workingHours: workingHours,
    markedBySomeoneElse: markedBySomeoneElse,
    canCheckIn: open && checkIn == null,
    canCheckOut: open && checkIn != null,
    blockedReason: blockedReason,
  );
}
