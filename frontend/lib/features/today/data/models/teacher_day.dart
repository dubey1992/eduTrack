/// A teacher's day as the server sees it (`GET timetable/today`,
/// docs/teacher-app.md T1).
///
/// The server answers with the school's own date and clock, so nothing here
/// works out what day it is or which period is under way - it reads both.
class TeacherDay {
  const TeacherDay({
    required this.date,
    required this.now,
    required this.isOpen,
    required this.holidayName,
    required this.isHalfDay,
    required this.periods,
    required this.registers,
    required this.leaveToday,
    required this.leaveThisWeek,
    required this.reportsOwed,
    required this.registersOwed,
  });

  factory TeacherDay.fromJson(Map<String, dynamic> json) {
    final day = json['school_day'] as Map<String, dynamic>;
    final holiday = day['holiday'] as Map<String, dynamic>?;
    final leave = json['leave'] as Map<String, dynamic>;
    final owed = json['owed'] as Map<String, dynamic>;

    return TeacherDay(
      date: DateTime.parse(json['date'] as String),
      now: json['now'] as String,
      isOpen: day['is_open'] as bool,
      holidayName: holiday?['name'] as String?,
      isHalfDay: day['shape'] == 'half',
      periods: [for (final item in json['periods'] as List) TodayPeriod.fromJson(item as Map<String, dynamic>)],
      registers: [for (final item in json['registers'] as List) ClassRegister.fromJson(item as Map<String, dynamic>)],
      leaveToday: leave['today'] == null ? null : LeaveSpan.fromJson(leave['today'] as Map<String, dynamic>),
      leaveThisWeek: [for (final item in leave['this_week'] as List) LeaveSpan.fromJson(item as Map<String, dynamic>)],
      reportsOwed: owed['reports'] as int,
      registersOwed: owed['registers'] as int,
    );
  }

  /// The school's date, not the phone's.
  final DateTime date;

  /// The school's wall clock when the answer was made, `HH:mm`.
  final String now;

  /// False on a holiday or a day the school does not run.
  final bool isOpen;
  final String? holidayName;
  final bool isHalfDay;

  final List<TodayPeriod> periods;
  final List<ClassRegister> registers;

  final LeaveSpan? leaveToday;
  final List<LeaveSpan> leaveThisWeek;

  final int reportsOwed;
  final int registersOwed;

  int get owed => reportsOwed + registersOwed;

  /// Leave this week other than the one covering today.
  List<LeaveSpan> get otherLeaveThisWeek => [
    for (final leave in leaveThisWeek)
      if (leave.id != leaveToday?.id) leave,
  ];
}

enum PeriodState {
  done('done'),
  current('current'),
  upcoming('upcoming');

  const PeriodState(this.apiValue);

  final String apiValue;

  static PeriodState fromApiValue(String value) =>
      PeriodState.values.firstWhere((state) => state.apiValue == value, orElse: () => PeriodState.upcoming);
}

class TodayPeriod {
  const TodayPeriod({
    required this.timetableEntryId,
    required this.periodNumber,
    required this.startTime,
    required this.endTime,
    required this.state,
    required this.classSectionId,
    required this.classSection,
    required this.subject,
    this.subjectId,
    required this.reportFiled,
    required this.reportId,
  });

  factory TodayPeriod.fromJson(Map<String, dynamic> json) {
    final report = json['report'] as Map<String, dynamic>;

    return TodayPeriod(
      timetableEntryId: json['timetable_entry_id'] as int,
      periodNumber: json['period_number'] as int,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      state: PeriodState.fromApiValue(json['state'] as String),
      classSectionId: json['class_section_id'] as int,
      classSection: json['class_section'] as String,
      subject: json['subject'] as String,
      subjectId: json['subject_id'] as int?,
      reportFiled: report['filed'] as bool,
      reportId: report['id'] as int?,
    );
  }

  final int timetableEntryId;
  final int periodNumber;

  /// `HH:mm` on the school's clock.
  final String startTime;
  final String endTime;
  final PeriodState state;
  final int classSectionId;
  final String classSection;
  final String subject;

  /// For the report's syllabus topics. Optional so an older server's answer
  /// still reads; without it the report form offers no topic.
  final int? subjectId;
  final bool reportFiled;
  final int? reportId;

  /// A report is owed once the period has begun, not before.
  bool get reportOwed => !reportFiled && state != PeriodState.upcoming;
}

/// The register of a class this teacher is class teacher of.
class ClassRegister {
  const ClassRegister({required this.classSectionId, required this.classSection, required this.submitted});

  factory ClassRegister.fromJson(Map<String, dynamic> json) => ClassRegister(
    classSectionId: json['class_section_id'] as int,
    classSection: json['class_section'] as String,
    submitted: json['submitted'] as bool,
  );

  final int classSectionId;
  final String classSection;
  final bool submitted;
}

class LeaveSpan {
  const LeaveSpan({required this.id, required this.leaveType, required this.startDate, required this.endDate});

  factory LeaveSpan.fromJson(Map<String, dynamic> json) => LeaveSpan(
    id: json['id'] as int,
    leaveType: json['leave_type'] as String,
    startDate: DateTime.parse(json['start_date'] as String),
    endDate: DateTime.parse(json['end_date'] as String),
  );

  final int id;

  /// The API's value, e.g. `casual`.
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
}
