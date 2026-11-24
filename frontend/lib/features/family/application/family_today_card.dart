import 'package:intl/intl.dart';

import '../../../core/home_widget/today_card.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../data/models/family_day.dart';

/// The Family app's home-screen widget for one child, from the same answer
/// Home reads (docs/mobile-apps-review.md, M10, 6.1): today's register, the
/// bus, and the next fee.
///
/// The bus line says where things stood when the phone last asked - "On the
/// bus to school, boarded 7:42 AM" - never a live "4 minutes away": the
/// widget is refreshed about every half hour, not every minute.
TodayCard familyTodayCard(String childName, FamilyToday today, DateTime now) {
  final asOf = 'as of ${DateFormat('h:mm a').format(now)}';

  final lines = <String>[
    if (!today.isOpen) today.holidayName == null ? 'No school today' : 'No school today: ${today.holidayName}',
    if (today.isOpen) 'Today: ${today.attendance?.mark.label ?? AttendanceMark.notMarked.label}',
    ?_busLine(today.bus),
    ?_feeLine(today.fee),
  ];

  return TodayCard(title: childName, lines: lines.take(TodayCard.maxLines).toList(), asOf: asOf);
}

String? _busLine(TodayBus? bus) {
  if (bus == null) return null;

  // The trip that says the most: one under way, else the latest of the day.
  final trip = bus.trips.where((t) => t.isRunning).lastOrNull ?? bus.afternoon ?? bus.morning;
  if (trip == null) {
    return bus.pickupTime == null ? null : 'Bus pick-up ${formatClock(bus.pickupTime!)}';
  }

  final at = trip.riderStatus == 'dropped' ? trip.droppedAt : trip.boardedAt;

  // Boarding and drop times come on the school's clock, "07:42".
  return at == null ? 'Bus: ${trip.summary}' : 'Bus: ${trip.summary}, ${formatClock(at)}';
}

String? _feeLine(NextFee? fee) {
  if (fee == null) return null;

  final amount = formatCurrency(fee.amount, fee.currencyCode);

  return fee.isOverdue ? 'Fees: $amount overdue' : 'Fees: $amount due ${formatDate(fee.dueDate)}';
}
