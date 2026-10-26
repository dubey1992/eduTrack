import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/today/data/models/teacher_day.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';

/// Answers Today from memory. [days] are handed out one per call, the last
/// one repeating, so a test can show what a refresh brings.
class FakeTodayRepository implements TodayRepository {
  FakeTodayRepository({List<TeacherDay>? days, this.failWith}) : _days = days ?? [teacherDay()];

  final List<TeacherDay> _days;
  Failure? failWith;
  int calls = 0;

  @override
  Future<TeacherDay> today() async {
    calls++;
    if (failWith != null) throw failWith!;

    return _days[(calls - 1).clamp(0, _days.length - 1)];
  }
}

/// Monday 26 October 2026: period 1 over without a report, period 3 under
/// way with one, period 5 to come; class teacher of Grade 8 A.
TeacherDay teacherDay({
  bool isOpen = true,
  String? holidayName,
  bool isHalfDay = false,
  List<TodayPeriod>? periods,
  List<ClassRegister>? registers,
  LeaveSpan? leaveToday,
  List<LeaveSpan> leaveThisWeek = const [],
  int? reportsOwed,
  int? registersOwed,
}) {
  final thePeriods = periods ?? (isOpen ? samplePeriods : const <TodayPeriod>[]);
  final theRegisters =
      registers ??
      (isOpen
          ? const [ClassRegister(classSectionId: 81, classSection: 'Grade 8 A', submitted: false)]
          : const <ClassRegister>[]);
  final owes = isOpen && leaveToday == null;

  return TeacherDay(
    date: DateTime(2026, 10, 26),
    now: '11:05',
    isOpen: isOpen,
    holidayName: holidayName,
    isHalfDay: isHalfDay,
    periods: thePeriods,
    registers: theRegisters,
    leaveToday: leaveToday,
    leaveThisWeek: leaveThisWeek,
    reportsOwed: reportsOwed ?? (owes ? thePeriods.where((p) => p.reportOwed).length : 0),
    registersOwed: registersOwed ?? (owes ? theRegisters.where((r) => !r.submitted).length : 0),
  );
}

const samplePeriods = [
  TodayPeriod(
    timetableEntryId: 11,
    periodNumber: 1,
    startTime: '09:00',
    endTime: '09:45',
    state: PeriodState.done,
    classSectionId: 81,
    classSection: 'Grade 8 A',
    subject: 'Mathematics',
    subjectId: 31,
    reportFiled: false,
    reportId: null,
  ),
  TodayPeriod(
    timetableEntryId: 13,
    periodNumber: 3,
    startTime: '11:00',
    endTime: '11:45',
    state: PeriodState.current,
    classSectionId: 91,
    classSection: 'Grade 9 A',
    subject: 'Science',
    reportFiled: true,
    reportId: 501,
  ),
  TodayPeriod(
    timetableEntryId: 15,
    periodNumber: 5,
    startTime: '13:30',
    endTime: '14:15',
    state: PeriodState.upcoming,
    classSectionId: 81,
    classSection: 'Grade 8 A',
    subject: 'Mathematics',
    reportFiled: false,
    reportId: null,
  ),
];
