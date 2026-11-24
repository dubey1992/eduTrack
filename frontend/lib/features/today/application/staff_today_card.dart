import 'package:intl/intl.dart';

import '../../../core/home_widget/today_card.dart';
import '../../../core/utils/date_format.dart';
import '../../check_in/data/models/my_attendance_day.dart';
import '../data/models/teacher_day.dart';

/// The Staff app's home-screen widget, from the same answers its Today
/// screen reads (docs/mobile-apps-review.md, M10, 6.1): the period now or
/// next, the register, the reports still owed, and checking in.
///
/// [me] is null where the school does not use check-in, or it could not be
/// read - the line is then left out rather than guessed.
TodayCard staffTodayCard(TeacherDay day, MyAttendanceDay? me, DateTime now) {
  final asOf = 'as of ${DateFormat('h:mm a').format(now)}';

  if (!day.isOpen) {
    return TodayCard(
      title: 'Today',
      lines: [day.holidayName == null ? 'The school is closed today' : 'Holiday: ${day.holidayName}'],
      asOf: asOf,
    );
  }

  if (day.leaveToday != null && !day.isHalfDay) {
    return TodayCard(title: 'Today', lines: const ['You are on leave today'], asOf: asOf);
  }

  final lines = <String>[
    _periodLine(day.periods),
    ?_registerLine(day.registers),
    ?_reportsLine(day),
    ?_checkInLine(me),
  ];

  return TodayCard(title: 'Today', lines: lines.take(TodayCard.maxLines).toList(), asOf: asOf);
}

String _periodLine(List<TodayPeriod> periods) {
  final current = periods.where((p) => p.state == PeriodState.current).firstOrNull;
  if (current != null) return 'Now: P${current.periodNumber} ${current.subject} · ${current.classSection}';

  final next = periods.where((p) => p.state == PeriodState.upcoming).firstOrNull;
  if (next != null) {
    return 'Next: P${next.periodNumber} ${next.subject} · ${next.classSection} at ${formatClock(next.startTime)}';
  }

  return periods.isEmpty ? 'No periods today' : 'No more periods today';
}

String? _registerLine(List<ClassRegister> registers) {
  if (registers.isEmpty) return null;

  final waiting = registers.where((r) => !r.submitted).toList();
  if (waiting.isEmpty) return 'Register taken';

  return waiting.length == 1
      ? 'Register not taken: ${waiting.single.classSection}'
      : '${waiting.length} registers not taken';
}

String? _reportsLine(TeacherDay day) {
  if (day.periods.isEmpty) return null;
  if (day.reportsOwed == 0) return 'Reports up to date';

  return day.reportsOwed == 1 ? '1 report owed' : '${day.reportsOwed} reports owed';
}

String? _checkInLine(MyAttendanceDay? me) {
  if (me == null || me.hidden) return null;

  final checkIn = me.checkIn;
  if (checkIn != null) return 'Checked in at ${formatClock(checkIn)}';

  return me.canCheckIn ? 'Not checked in yet' : null;
}
