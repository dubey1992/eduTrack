import 'package:intl/intl.dart';

import '../../../core/home_widget/today_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/date_format.dart';
import '../../check_in/data/models/my_attendance_day.dart';
import '../data/models/teacher_day.dart';

/// The Staff app's home-screen widget, from the same answers its Today
/// screen reads (docs/mobile-apps-review.md, M10, 6.1): the period now or
/// next, the register, the reports still owed, and checking in.
///
/// [me] is null where the school does not use check-in, or it could not be
/// read - the line is then left out rather than guessed.
TodayCard staffTodayCard(AppLocalizations l10n, TeacherDay day, MyAttendanceDay? me, DateTime now) {
  final asOf = l10n.widgetAsOf(DateFormat('h:mm a').format(now));

  if (!day.isOpen) {
    return TodayCard(
      title: l10n.widgetToday,
      lines: [day.holidayName == null ? l10n.widgetSchoolClosed : l10n.widgetHoliday(day.holidayName!)],
      asOf: asOf,
    );
  }

  if (day.leaveToday != null && !day.isHalfDay) {
    return TodayCard(title: l10n.widgetToday, lines: [l10n.widgetOnLeave], asOf: asOf);
  }

  final lines = <String>[
    _periodLine(l10n, day.periods),
    ?_registerLine(l10n, day.registers),
    ?_reportsLine(l10n, day),
    ?_checkInLine(l10n, me),
  ];

  return TodayCard(title: l10n.widgetToday, lines: lines.take(TodayCard.maxLines).toList(), asOf: asOf);
}

String _periodLine(AppLocalizations l10n, List<TodayPeriod> periods) {
  final current = periods.where((p) => p.state == PeriodState.current).firstOrNull;
  if (current != null) return l10n.widgetNowPeriod(current.periodNumber, current.subject, current.classSection);

  final next = periods.where((p) => p.state == PeriodState.upcoming).firstOrNull;
  if (next != null) {
    return l10n.widgetNextPeriod(next.periodNumber, next.subject, next.classSection, formatClock(next.startTime));
  }

  return periods.isEmpty ? l10n.widgetNoPeriods : l10n.widgetNoMorePeriods;
}

String? _registerLine(AppLocalizations l10n, List<ClassRegister> registers) {
  if (registers.isEmpty) return null;

  final waiting = registers.where((r) => !r.submitted).toList();
  if (waiting.isEmpty) return l10n.widgetRegisterTaken;

  return waiting.length == 1
      ? l10n.widgetRegisterNotTaken(waiting.single.classSection)
      : l10n.widgetRegistersNotTaken(waiting.length);
}

String? _reportsLine(AppLocalizations l10n, TeacherDay day) {
  if (day.periods.isEmpty) return null;
  if (day.reportsOwed == 0) return l10n.widgetReportsUpToDate;

  return l10n.widgetReportsOwed(day.reportsOwed);
}

String? _checkInLine(AppLocalizations l10n, MyAttendanceDay? me) {
  if (me == null || me.hidden) return null;

  final checkIn = me.checkIn;
  if (checkIn != null) return l10n.widgetCheckedIn(formatClock(checkIn));

  return me.canCheckIn ? l10n.widgetNotCheckedIn : null;
}
