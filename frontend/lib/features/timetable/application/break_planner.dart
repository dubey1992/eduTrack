import '../data/models/period.dart';
import '../data/models/school_break.dart';

/// The thinking behind the Add Break form: where a break probably goes, and
/// what a chosen time would run into. Pure - handed the day's periods and
/// breaks, it returns answers - so the form explains itself before anything
/// is saved.

int minutesOf(String clock) {
  final parts = clock.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String clockOf(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// A slot of the day: a period or a break, by its times.
class Slot {
  const Slot(this.label, this.start, this.end);

  final String label;
  final int start;
  final int end;

  String get times => '${clockOf(start)}-${clockOf(end)}';
}

List<Slot> slotsOf(List<Period> periods, List<SchoolBreak> breaks, {int? ignoringBreak}) {
  return [
    for (final period in periods)
      Slot('Period ${period.periodNumber}', minutesOf(period.startTime), minutesOf(period.endTime)),
    for (final found in breaks)
      if (found.id != ignoringBreak) Slot('the ${found.name}', minutesOf(found.startTime), minutesOf(found.endTime)),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// Where a break of [length] minutes probably goes.
///
/// A free gap long enough wins - the first one for a short break, the one
/// nearest the middle of the day for lunch. With no gap, it goes right after
/// a period: the second for a short break, the one ending nearest the middle
/// of the day for lunch - and making room moves the rest back.
({String start, String end})? suggest(List<Slot> day, int length, {required bool lunch}) {
  if (day.isEmpty) return null;

  final middle = (day.first.start + day.last.end) ~/ 2;
  int nearestMiddle(int a, int b) => (a - middle).abs().compareTo((b - middle).abs());

  final gaps = <int>[
    for (var i = 0; i + 1 < day.length; i++)
      if (day[i + 1].start - day[i].end >= length) day[i].end,
  ];

  final int start;
  if (gaps.isNotEmpty) {
    start = lunch ? (gaps..sort(nearestMiddle)).first : gaps.first;
  } else if (lunch) {
    start = (day.map((slot) => slot.end).toList()..sort(nearestMiddle)).first;
  } else {
    start = day[day.length > 1 ? 1 : 0].end;
  }

  return (start: clockOf(start), end: clockOf(start + length));
}

/// What a break at these times would run into.
///
/// [startsDuring] can only be fixed by moving the break; [overlaps] can be
/// fixed by moving the later periods back by [roomNeeded] minutes.
({Slot? startsDuring, Slot? overlaps, int roomNeeded}) clashes(List<Slot> day, String start, String end) {
  final from = minutesOf(start);
  final to = minutesOf(end);

  for (final slot in day) {
    if (slot.start < from && from < slot.end) return (startsDuring: slot, overlaps: null, roomNeeded: 0);
  }

  final later = day.where((slot) => slot.start >= from).toList();
  final hit = later.where((slot) => slot.start < to).firstOrNull;

  return (startsDuring: null, overlaps: hit, roomNeeded: hit == null ? 0 : to - later.first.start);
}
