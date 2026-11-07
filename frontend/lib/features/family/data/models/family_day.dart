/// One child's day, for the Family app's home screen
/// (`GET /family/children/{id}/today`, school/family_day.py).
class FamilyToday {
  const FamilyToday({
    required this.date,
    required this.isOpen,
    required this.holidayName,
    required this.attendance,
    required this.bus,
    required this.fee,
    required this.periods,
    required this.breaks,
  });

  factory FamilyToday.fromJson(Map<String, dynamic> json) {
    final day = json['school_day'] as Map<String, dynamic>;
    final holiday = day['holiday'] as Map<String, dynamic>?;
    final attendance = json['attendance'] as Map<String, dynamic>?;
    final bus = json['bus'] as Map<String, dynamic>?;
    final fee = json['fee'] as Map<String, dynamic>?;

    return FamilyToday(
      date: DateTime.parse(json['date'] as String),
      isOpen: day['is_open'] as bool,
      holidayName: holiday?['name'] as String?,
      attendance: attendance == null ? null : TodayAttendance.fromJson(attendance),
      bus: bus == null ? null : TodayBus.fromJson(bus),
      fee: fee == null ? null : NextFee.fromJson(fee),
      periods: [for (final p in json['periods'] as List<dynamic>) TodayPeriod.fromJson(p as Map<String, dynamic>)],
      breaks: [for (final b in json['breaks'] as List<dynamic>) TodayBreak.fromJson(b as Map<String, dynamic>)],
    );
  }

  /// The school's today, not the phone's.
  final DateTime date;
  final bool isOpen;
  final String? holidayName;

  /// Null on a day the school is closed.
  final TodayAttendance? attendance;

  /// Null for a child the school does not carry.
  final TodayBus? bus;

  /// Null when nothing is owed.
  final NextFee? fee;
  final List<TodayPeriod> periods;
  final List<TodayBreak> breaks;
}

/// What the register says: present, absent, leave or not marked yet.
enum AttendanceMark {
  present('present', 'Present'),
  absent('absent', 'Absent'),
  leave('leave', 'On leave'),
  notMarked('not_marked', 'Not marked yet');

  const AttendanceMark(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AttendanceMark fromApiValue(String? value) =>
      values.firstWhere((mark) => mark.apiValue == value, orElse: () => notMarked);
}

class TodayAttendance {
  const TodayAttendance({required this.mark, required this.remarks});

  factory TodayAttendance.fromJson(Map<String, dynamic> json) => TodayAttendance(
    mark: AttendanceMark.fromApiValue(json['status'] as String?),
    remarks: json['remarks'] as String?,
  );

  final AttendanceMark mark;
  final String? remarks;
}

class TodayBus {
  const TodayBus({
    required this.route,
    required this.stop,
    required this.pickupTime,
    required this.dropTime,
    required this.trips,
  });

  factory TodayBus.fromJson(Map<String, dynamic> json) => TodayBus(
    route: json['route'] as String,
    stop: json['stop'] as String?,
    pickupTime: json['pickup_time'] as String?,
    dropTime: json['drop_time'] as String?,
    trips: [for (final t in json['trips'] as List<dynamic>) BusTrip.fromJson(t as Map<String, dynamic>)],
  );

  final String route;
  final String? stop;

  /// "07:30", the school's clock.
  final String? pickupTime;
  final String? dropTime;
  final List<BusTrip> trips;

  BusTrip? get morning => trips.where((trip) => trip.isPickup).lastOrNull;

  BusTrip? get afternoon => trips.where((trip) => !trip.isPickup).lastOrNull;
}

class BusTrip {
  const BusTrip({
    required this.direction,
    required this.status,
    required this.riderStatus,
    required this.boardedAt,
    required this.droppedAt,
  });

  factory BusTrip.fromJson(Map<String, dynamic> json) => BusTrip(
    direction: json['direction'] as String,
    status: json['status'] as String,
    riderStatus: json['rider_status'] as String?,
    boardedAt: json['boarded_at'] as String?,
    droppedAt: json['dropped_at'] as String?,
  );

  /// `pickup` (to school) or `drop` (home).
  final String direction;

  /// `in_progress`, `completed` or `cancelled`.
  final String status;

  /// `pending`, `boarded`, `dropped` or `absent`; null when the child is not
  /// on this trip's list.
  final String? riderStatus;
  final String? boardedAt;
  final String? droppedAt;

  bool get isPickup => direction == 'pickup';

  bool get isRunning => status == 'in_progress';

  /// The trip in plain words, as the parent reads it.
  String get summary {
    if (status == 'cancelled') return 'Trip cancelled';

    return switch (riderStatus) {
      'boarded' => isPickup ? 'On the bus to school' : 'On the bus home',
      'dropped' => isPickup ? 'Reached school' : 'Dropped at the stop',
      'absent' => 'Did not take the bus',
      _ => isRunning ? 'Bus on its way' : 'Trip ended',
    };
  }
}

class NextFee {
  const NextFee({
    required this.label,
    required this.dueDate,
    required this.amount,
    required this.currencyCode,
    required this.isOverdue,
  });

  factory NextFee.fromJson(Map<String, dynamic> json) => NextFee(
    label: json['label'] as String,
    dueDate: DateTime.parse(json['due_date'] as String),
    amount: double.parse(json['amount'] as String),
    currencyCode: json['currency_code'] as String,
    isOverdue: json['is_overdue'] as bool,
  );

  final String label;
  final DateTime dueDate;
  final double amount;
  final String currencyCode;
  final bool isOverdue;
}

class TodayPeriod {
  const TodayPeriod({
    required this.number,
    required this.startTime,
    required this.endTime,
    required this.state,
    required this.subject,
    required this.teacher,
  });

  factory TodayPeriod.fromJson(Map<String, dynamic> json) => TodayPeriod(
    number: json['period_number'] as int,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    state: json['state'] as String,
    subject: json['subject'] as String?,
    teacher: json['teacher'] as String?,
  );

  final int number;
  final String startTime;
  final String endTime;

  /// `done`, `current` or `upcoming`.
  final String state;
  final String? subject;
  final String? teacher;
}

class TodayBreak {
  const TodayBreak({required this.name, required this.startTime, required this.endTime});

  factory TodayBreak.fromJson(Map<String, dynamic> json) => TodayBreak(
    name: json['name'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
  );

  final String name;
  final String startTime;
  final String endTime;
}
