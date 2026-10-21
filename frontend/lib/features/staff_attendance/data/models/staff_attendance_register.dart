import '../../../holidays/data/models/holiday.dart';
import 'staff_attendance_status.dart';

/// One staff member's row in a school's daily register - [status]/etc. are
/// null until the day has been marked.
class StaffRosterEntry {
  const StaffRosterEntry({
    required this.staffProfileId,
    required this.employeeId,
    required this.name,
    required this.departmentName,
    required this.status,
    required this.checkIn,
    required this.checkOut,
    required this.workingHours,
    required this.remarks,
    this.timesFromDevice = false,
    this.markedByDevice = false,
    this.late = false,
  });

  factory StaffRosterEntry.fromJson(Map<String, dynamic> json) {
    return StaffRosterEntry(
      staffProfileId: json['staff_profile_id'] as int,
      employeeId: json['employee_id'] as String,
      name: json['name'] as String,
      departmentName: json['department_name'] as String?,
      status: json['status'] == null ? null : StaffAttendanceStatus.fromApiValue(json['status'] as String),
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      workingHours: json['working_hours'] as String?,
      remarks: json['remarks'] as String?,
      timesFromDevice: json['times_from_device'] as bool? ?? false,
      markedByDevice: json['marked_by_device'] as bool? ?? false,
      late: json['late'] as bool? ?? false,
    );
  }

  final int staffProfileId;
  final String employeeId;
  final String name;
  final String? departmentName;
  final StaffAttendanceStatus? status;
  final String? checkIn;
  final String? checkOut;
  final String? workingHours;
  final String? remarks;

  /// The times came off a fingerprint reader rather than being typed
  /// (docs/biometric.md, B3). Only ever true for a day nobody has marked
  /// yet - once it is saved the times are the register's own.
  final bool timesFromDevice;

  /// A punch marked this day, not a person (docs/biometric.md, B5). The row
  /// exists and nobody's name is on it, which is what the screen says rather
  /// than implying somebody decided it.
  final bool markedByDevice;

  /// Checked in after the first period of the school's day. Derived by the
  /// server from the timetable - the same rule the staff report counts by -
  /// and never a status: somebody who arrived at 09:05 was present.
  final bool late;

  StaffRosterEntry copyWith({
    StaffAttendanceStatus? status,
    String? checkIn,
    String? checkOut,
    String? remarks,
    bool clearCheckIn = false,
    bool clearCheckOut = false,
  }) {
    return StaffRosterEntry(
      staffProfileId: staffProfileId,
      employeeId: employeeId,
      name: name,
      departmentName: departmentName,
      status: status ?? this.status,
      checkIn: clearCheckIn ? null : (checkIn ?? this.checkIn),
      checkOut: clearCheckOut ? null : (checkOut ?? this.checkOut),
      workingHours: workingHours,
      remarks: remarks ?? this.remarks,
      timesFromDevice: timesFromDevice,
      markedByDevice: markedByDevice,
      late: late,
    );
  }
}

/// A school's (optionally department-filtered) staff attendance for one day
/// - the active roster, each paired with its mark (or none if [submitted]
/// is false).
class StaffAttendanceRegister {
  const StaffAttendanceRegister({
    required this.schoolId,
    required this.attendanceDate,
    required this.submitted,
    required this.staff,
    this.holiday,
  });

  factory StaffAttendanceRegister.fromJson(Map<String, dynamic> json) {
    return StaffAttendanceRegister(
      schoolId: json['school_id'] as int,
      attendanceDate: json['attendance_date'] as String,
      submitted: json['submitted'] as bool,
      staff: (json['staff'] as List).cast<Map<String, dynamic>>().map(StaffRosterEntry.fromJson).toList(),
      holiday: json['holiday'] == null ? null : HolidaySummary.fromJson(json['holiday'] as Map<String, dynamic>),
    );
  }

  final int schoolId;
  final String attendanceDate;
  final bool submitted;
  final List<StaffRosterEntry> staff;

  /// Set when the day is on the school's calendar; the server refuses to mark it.
  final HolidaySummary? holiday;
}
