import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/utils/school_clock.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// The client's half of per-school timezones: what day it is at the school,
/// which is not necessarily what day it is in the browser.
///
/// The clock reports the school's time as "the reading taken when the session
/// was fetched, plus however long has passed since". So the parsing and the
/// passage of time are checked separately: a frozen anchor pins the parsing,
/// and a live one pins the arithmetic.
void main() {
  /// A clock reading [wall] at the school, anchored [elapsed] ago.
  SchoolClock clockReading(DateTime wall, {Duration elapsed = Duration.zero}) {
    return SchoolClock(
      timezone: 'Asia/Kolkata',
      schoolTimeAtAnchor: wall,
      anchorUtc: DateTime.now().toUtc().subtract(elapsed),
    );
  }

  group('reading the session payload', () {
    test('keeps the school clock reading instead of converting it', () {
      final clock = SchoolClock.fromSession(
        timezone: 'Asia/Kolkata',
        currentTime: '2026-09-17T00:30:00+05:30',
      );

      expect(clock.timezone, 'Asia/Kolkata');
      // Half past midnight on the 17th, as the school reads it. The same
      // instant is still the 16th in UTC, and could be any date at all in
      // whatever zone the browser happens to be set to.
      expect(clock.schoolTimeAtAnchor, DateTime(2026, 9, 17, 0, 30));
      expect(clock.anchorUtc, DateTime.utc(2026, 9, 16, 19, 0));
    });

    test('reads a zone behind UTC just as faithfully', () {
      final clock = SchoolClock.fromSession(
        timezone: 'America/New_York',
        currentTime: '2026-09-15T22:00:00-04:00',
      );

      // Ten at night on the 15th in New York; the 16th has already begun in
      // UTC.
      expect(clock.schoolTimeAtAnchor, DateTime(2026, 9, 15, 22, 0));
      expect(clock.anchorUtc, DateTime.utc(2026, 9, 16, 2, 0));
    });

    test('falls back to the device clock when the payload is unusable', () {
      expect(SchoolClock.fromSession(timezone: 'Asia/Kolkata', currentTime: '').timezone, 'device');
      expect(SchoolClock.fromSession(timezone: 'Asia/Kolkata', currentTime: 'not a time').timezone, 'device');
    });
  });

  group('telling the time', () {
    test('carries elapsed time forward from the anchor', () {
      final clock = clockReading(DateTime(2026, 9, 17, 0, 30), elapsed: const Duration(hours: 2));

      expect(clock.now.hour, 2);
      // Two hours past midnight is still the same day at the school.
      expect(clock.todayIso, '2026-09-17');
    });

    test('rolls over midnight without refetching the session', () {
      final clock = clockReading(DateTime(2026, 9, 16, 23, 30), elapsed: const Duration(hours: 1));

      expect(clock.todayIso, '2026-09-17');
    });

    test('today is midnight, so a date picker gets a clean bound', () {
      expect(clockReading(DateTime(2026, 9, 17, 14, 45, 12)).today, DateTime(2026, 9, 17));
    });

    test('isToday answers on the school calendar', () {
      final clock = clockReading(DateTime(2026, 9, 17, 0, 30));

      expect(clock.isToday(DateTime(2026, 9, 17, 23, 59)), isTrue);
      // The 16th is still today in UTC at that moment, but not at the school.
      expect(clock.isToday(DateTime(2026, 9, 16)), isFalse);
    });

    test('pads todayIso so it matches the format the API expects', () {
      expect(clockReading(DateTime(2026, 1, 5)).todayIso, '2026-01-05');
    });
  });

  group('the session model', () {
    test('builds a clock from the timezone the API sent', () {
      final user = AuthenticatedUser.fromJson({
        'id': 1,
        'name': 'Priya Sharma',
        'email': 'priya@sunrise.test',
        'role': 'SCHOOL_ADMIN',
        'timezone': 'Asia/Kolkata',
        'current_time': '2026-09-17T00:30:00+05:30',
      });

      expect(user.clock.timezone, 'Asia/Kolkata');
      expect(user.clock.schoolTimeAtAnchor, DateTime(2026, 9, 17, 0, 30));
    });

    test('falls back to the device clock when a session carries no timezone', () {
      const user = AuthenticatedUser(
        id: 1,
        name: 'Priya Sharma',
        email: 'priya@sunrise.test',
        role: UserRole.schoolAdmin,
      );

      expect(user.clock.timezone, 'device');
    });
  });
}
