import 'package:intl/intl.dart';

import '../../../core/home_widget/today_card.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../data/models/family_day.dart';

/// The Family app's home-screen widget for one child, from the same answer
/// Home reads (docs/mobile-apps-review.md, M10, 6.1): today's register, the
/// bus, and the next fee - in the parent's language (M11).
///
/// The bus line says where things stood when the phone last asked - "On the
/// bus to school, 7:42 AM" - never a live "4 minutes away": the widget is
/// refreshed about every half hour, not every minute.
TodayCard familyTodayCard(AppLocalizations l10n, String childName, FamilyToday today, DateTime now) {
  final asOf = l10n.widgetAsOf(DateFormat('h:mm a').format(now));

  final lines = <String>[
    if (!today.isOpen) today.holidayName == null ? l10n.widgetNoSchool : l10n.widgetNoSchoolHoliday(today.holidayName!),
    if (today.isOpen) l10n.widgetAttendance(_mark(l10n, today.attendance?.mark ?? AttendanceMark.notMarked)),
    ?_busLine(l10n, today.bus),
    ?_feeLine(l10n, today.fee),
  ];

  return TodayCard(title: childName, lines: lines.take(TodayCard.maxLines).toList(), asOf: asOf);
}

String _mark(AppLocalizations l10n, AttendanceMark mark) => switch (mark) {
  AttendanceMark.present => l10n.widgetMarkPresent,
  AttendanceMark.absent => l10n.widgetMarkAbsent,
  AttendanceMark.leave => l10n.widgetMarkLeave,
  AttendanceMark.notMarked => l10n.widgetMarkNotMarked,
};

String? _busLine(AppLocalizations l10n, TodayBus? bus) {
  if (bus == null) return null;

  // The trip that says the most: one under way, else the latest of the day.
  final trip = bus.trips.where((t) => t.isRunning).lastOrNull ?? bus.afternoon ?? bus.morning;
  if (trip == null) {
    return bus.pickupTime == null ? null : l10n.widgetBusPickup(formatClock(bus.pickupTime!));
  }

  final status = _tripStatus(l10n, trip);
  final at = trip.riderStatus == 'dropped' ? trip.droppedAt : trip.boardedAt;

  // Boarding and drop times come on the school's clock, "07:42".
  return at == null ? l10n.widgetBus(status) : l10n.widgetBusAt(status, formatClock(at));
}

/// BusTrip.summary, in the parent's language.
String _tripStatus(AppLocalizations l10n, BusTrip trip) {
  if (trip.status == 'cancelled') return l10n.widgetTripCancelled;

  return switch (trip.riderStatus) {
    'boarded' when !trip.isRunning => trip.isPickup ? l10n.widgetReachedSchool : l10n.widgetTripEnded,
    'boarded' => trip.isPickup ? l10n.widgetOnBusToSchool : l10n.widgetOnBusHome,
    'dropped' => trip.isPickup ? l10n.widgetReachedSchool : l10n.widgetDropped,
    'absent' => l10n.widgetNoBus,
    _ => trip.isRunning ? l10n.widgetBusOnItsWay : l10n.widgetTripEnded,
  };
}

String? _feeLine(AppLocalizations l10n, NextFee? fee) {
  if (fee == null) return null;

  final amount = formatCurrency(fee.amount, fee.currencyCode);

  return fee.isOverdue ? l10n.widgetFeesOverdue(amount) : l10n.widgetFeesDue(amount, formatDate(fee.dueDate));
}
