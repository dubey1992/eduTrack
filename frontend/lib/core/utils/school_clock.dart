/// What day it is at the school the signed-in user belongs to.
///
/// The browser's own timezone is whatever the person's laptop is set to,
/// which for a multi-nation product is nobody's school in particular. So the
/// client never asks the device what day it is: the session carries the
/// school's zone and the school's current time, and everything measures
/// against those.
///
/// Timestamps coming back from the API are UTC instants, and Flutter has no
/// timezone database to convert them with, so the API sends a rendered label
/// alongside each one (`sent_at_label`, `started_at_label`). This class is
/// for the other half of the problem - the dates the client itself decides,
/// like a date picker's default and its upper bound.
class SchoolClock {
  const SchoolClock({required this.timezone, required this.schoolTimeAtAnchor, required this.anchorUtc});

  /// Builds a clock from the session payload: an IANA name and the school's
  /// current time as an ISO string carrying its offset, e.g.
  /// `2026-09-17T00:30:00+05:30`.
  factory SchoolClock.fromSession({required String timezone, required String currentTime}) {
    // The wall-clock half, parsed without its offset so it stays the reading
    // on the school's clock rather than being converted to the browser's.
    final wall = DateTime.tryParse(currentTime.length >= 19 ? currentTime.substring(0, 19) : currentTime);
    final instant = DateTime.tryParse(currentTime);

    if (wall == null || instant == null) return SchoolClock.device();

    return SchoolClock(timezone: timezone, schoolTimeAtAnchor: wall, anchorUtc: instant.toUtc());
  }

  /// The fallback before anyone is signed in - the login screen has no school
  /// to ask, so the device's own clock is the only one available.
  factory SchoolClock.device() {
    final now = DateTime.now();

    return SchoolClock(timezone: 'device', schoolTimeAtAnchor: now, anchorUtc: now.toUtc());
  }

  /// The IANA name, e.g. `Asia/Kolkata`. `device` when there is no session.
  final String timezone;

  /// The reading on the school's clock when the session was fetched.
  final DateTime schoolTimeAtAnchor;

  /// The same moment in UTC, so elapsed time can be measured against it.
  final DateTime anchorUtc;

  /// The school's current time, carried forward from when the session was
  /// fetched.
  ///
  /// Elapsed time is added to the reading taken at the anchor, so a session
  /// left open across midnight still rolls over. A daylight-saving change
  /// mid-session would leave this an hour out until the session is refetched;
  /// that is the one case this deliberately does not chase, because handling
  /// it on the client would mean shipping the whole timezone database.
  DateTime get now => schoolTimeAtAnchor.add(DateTime.now().toUtc().difference(anchorUtc));

  /// Midnight at the start of the school's current day - the value to hand a
  /// date picker as its default or its bound.
  DateTime get today {
    final current = now;

    return DateTime(current.year, current.month, current.day);
  }

  /// The school's current date as `yyyy-MM-dd`, the form the API expects.
  String get todayIso {
    final date = today;

    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Whether a date falls on the school's current day.
  bool isToday(DateTime date) {
    final current = today;

    return date.year == current.year && date.month == current.month && date.day == current.day;
  }
}
