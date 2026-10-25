import '../../../staff_attendance/data/models/staff_attendance_status.dart';

/// The caller's own day on the staff register (`GET staff-attendance/me`,
/// docs/staff-check-in.md): whether they may check in or out now, and what
/// the register already says.
class MyAttendanceDay {
  const MyAttendanceDay({
    required this.date,
    required this.enabled,
    required this.radiusMetres,
    required this.isOpen,
    required this.onLeave,
    this.halfDayLeave = false,
    required this.status,
    required this.checkIn,
    required this.checkOut,
    required this.late,
    required this.workingHours,
    required this.markedBySomeoneElse,
    required this.canCheckIn,
    required this.canCheckOut,
    required this.blockedReason,
    this.unfinishedDay,
  });

  factory MyAttendanceDay.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;

    return MyAttendanceDay(
      date: DateTime.parse(json['date'] as String),
      enabled: json['enabled'] as bool,
      radiusMetres: json['radius_m'] as int,
      isOpen: (json['school_day'] as Map<String, dynamic>)['is_open'] as bool,
      onLeave: json['on_leave'] as bool,
      halfDayLeave: json['half_day_leave'] as bool? ?? false,
      status: status == null ? null : StaffAttendanceStatus.fromApiValue(status),
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      late: json['late'] as bool,
      workingHours: json['working_hours'] as String?,
      markedBySomeoneElse: json['marked_by_someone_else'] as bool,
      canCheckIn: json['can_check_in'] as bool,
      canCheckOut: json['can_check_out'] as bool,
      blockedReason: json['blocked_reason'] as String?,
      unfinishedDay: json['unfinished_day'] == null
          ? null
          : UnfinishedDay.fromJson(json['unfinished_day'] as Map<String, dynamic>),
    );
  }

  /// The school's date, not the phone's.
  final DateTime date;

  /// The school lets staff check in from the app at all.
  final bool enabled;
  final int radiusMetres;
  final bool isOpen;
  final bool onLeave;

  /// Approved half-day leave: they check in for the half they work, and the
  /// day becomes a half day.
  final bool halfDayLeave;

  /// What the register says for today, or null when nothing yet.
  final StaffAttendanceStatus? status;

  /// `HH:mm` on the school's clock.
  final String? checkIn;
  final String? checkOut;
  final bool late;

  /// "7h 25m", once both times exist.
  final String? workingHours;

  /// The office or a fingerprint reader put today's row there.
  final bool markedBySomeoneElse;

  final bool canCheckIn;
  final bool canCheckOut;

  /// Why neither is possible today, in the server's words.
  final String? blockedReason;

  /// A recent day they checked in to and never out of.
  final UnfinishedDay? unfinishedDay;

  /// Nothing for the app to show: the school marks staff in the office, or
  /// the day is one Today already explains (closed, or on leave).
  bool get hidden => !enabled || !isOpen || onLeave;
}

/// A day somebody checked in to from the app and never checked out of. The
/// leaving time is not knowable the next day, so the office adds it.
class UnfinishedDay {
  const UnfinishedDay({required this.date, required this.checkIn});

  factory UnfinishedDay.fromJson(Map<String, dynamic> json) =>
      UnfinishedDay(date: DateTime.parse(json['date'] as String), checkIn: json['check_in'] as String);

  final DateTime date;

  /// `HH:mm`.
  final String checkIn;
}
