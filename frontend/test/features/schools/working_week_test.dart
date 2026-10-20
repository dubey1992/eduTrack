import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:flutter_test/flutter_test.dart';

/// The days a school runs (docs/holidays.md).
///
/// Monday first, which is how the server stores it. A Sunday-to-Thursday week
/// is `1111001` — odd written down, and the only ordering where the index is
/// the weekday and there is no arithmetic to get wrong.
const monFri = '1111100';
const gulf = '1111001';
const sixDay = '1111110';
const halfSaturday = '1111120'; // the same six days, Saturday a half day

void main() {
  group('reading what the server sent', () {
    test('the default week', () {
      final week = WorkingWeek.fromApiValue(monFri);

      expect(week.dayNames, ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']);
      expect(week.length, 5);
    });

    test('a Sunday to Thursday week', () {
      final week = WorkingWeek.fromApiValue(gulf);

      expect(week.dayNames, ['monday', 'tuesday', 'wednesday', 'thursday', 'sunday']);
      expect(week.runsOn(6), isTrue);
      expect(week.runsOn(4), isFalse);
    });

    test('a six day week', () {
      expect(WorkingWeek.fromApiValue(sixDay).length, 6);
    });

    test('it round trips', () {
      for (final stored in [monFri, gulf, sixDay, '1111111', '0000001']) {
        expect(WorkingWeek.fromApiValue(stored).apiValue, stored, reason: stored);
      }
    });

    test("a date's own weekday lines up with the stored order", () {
      // 19 October 2026 is a Monday; the 25th is the Sunday after it.
      final week = WorkingWeek.fromApiValue(gulf);

      expect(week.runsOnDate(DateTime(2026, 10, 19)), isTrue);
      expect(week.runsOnDate(DateTime(2026, 10, 23)), isFalse);
      expect(week.runsOnDate(DateTime(2026, 10, 25)), isTrue);
    });
  });

  group('a week it cannot read', () {
    test('is the week the product assumed, never an empty screen', () {
      for (final bad in <Object?>[null, '', 'garbage', '11111', '11111111', '1111103', '0000000', 7]) {
        expect(WorkingWeek.fromApiValue(bad).apiValue, monFri, reason: '$bad');
      }
    });
  });

  group('how it reads to a person', () {
    test('a run of days is named as a range', () {
      expect(WorkingWeek.fromApiValue(monFri).summary, 'Monday to Friday');
      expect(WorkingWeek.fromApiValue(sixDay).summary, 'Monday to Saturday');
    });

    test('a range that wraps past Sunday is still a range', () {
      // The point of the wrap: "Sunday to Thursday" is how the people who
      // keep that week describe it, and listing five days is the same
      // information in a form nobody uses.
      expect(WorkingWeek.fromApiValue(gulf).summary, 'Sunday to Thursday');
    });

    test('days that are not a run are listed', () {
      // Monday, Wednesday, Friday.
      expect(WorkingWeek.fromApiValue('1010100').summary, 'Monday, Wednesday, Friday');
    });

    test('one day is that day', () {
      expect(WorkingWeek.fromApiValue('0000001').summary, 'Sunday');
    });

    test('all seven is not "Monday to Sunday"', () {
      expect(WorkingWeek.fromApiValue('1111111').summary, 'Every day');
    });
  });

  group('changing it', () {
    test('toggling a day leaves the rest alone', () {
      final saturdayToo = WorkingWeek.fromApiValue(monFri).toggled(5);

      expect(saturdayToo.apiValue, sixDay);
    });

    test('toggling twice is where it started', () {
      final week = WorkingWeek.fromApiValue(gulf);

      expect(week.toggled(2).toggled(2), week);
    });

    test('a week with nothing in it knows it', () {
      var week = WorkingWeek.fromApiValue(monFri);
      for (final index in [0, 1, 2, 3, 4]) {
        week = week.toggled(index);
      }

      // Not refused here - the form and the server both refuse to save it.
      // This type only has to be able to represent the half-finished state
      // somebody passes through while unticking days.
      expect(week.isEmpty, isTrue);
      expect(week.summary, 'No days');
    });
  });

  group('a day that is a half day', () {
    test('it is still a working day', () {
      // A shorter day, not a fraction of one. Nothing that counts working
      // days cares which shape they were.
      final week = WorkingWeek.fromApiValue(halfSaturday);

      expect(week.length, 6);
      expect(week.runsOn(5), isTrue);
      expect(week.dayNames, contains('saturday'));
    });

    test('its shape is readable', () {
      final week = WorkingWeek.fromApiValue(halfSaturday);

      expect(week.shapeOf(0), WorkingWeek.fullDay);
      expect(week.shapeOf(5), WorkingWeek.halfDay);
      expect(week.shapeOf(6), isNull);
      expect(week.isHalfDay(5), isTrue);
      expect(week.isHalfDay(0), isFalse);
    });

    test('it round trips, so an edit cannot quietly lose it', () {
      // The bug this exists to stop: a week the app cannot read falls back
      // to Monday to Friday, and saving the form writes that back.
      expect(WorkingWeek.fromApiValue(halfSaturday).apiValue, halfSaturday);
      expect(WorkingWeek.fromApiValue('2222222').apiValue, '2222222');
    });

    test('a date resolves to its shape', () {
      // 24 October 2026 is a Saturday.
      final week = WorkingWeek.fromApiValue(halfSaturday);

      expect(week.shapeOnDate(DateTime(2026, 10, 24)), WorkingWeek.halfDay);
      expect(week.shapeOnDate(DateTime(2026, 10, 19)), WorkingWeek.fullDay);
      expect(week.shapeOnDate(DateTime(2026, 10, 25)), isNull);
    });

    test('it is named on its own, because a range hides it', () {
      expect(WorkingWeek.fromApiValue(halfSaturday).summary, 'Monday to Saturday');
      expect(WorkingWeek.fromApiValue(halfSaturday).halfDayNote, 'Saturday is a half day.');
      expect(WorkingWeek.fromApiValue('1111122').halfDayNote, 'Saturday, Sunday are half days.');
      expect(WorkingWeek.fromApiValue(monFri).halfDayNote, isNull);
    });

    test('a character that is not a day state is still unreadable', () {
      expect(WorkingWeek.fromApiValue('1111103').apiValue, monFri);
    });

    test('turning it off and on again makes it full, which the field shows', () {
      final week = WorkingWeek.fromApiValue(halfSaturday);

      expect(week.toggled(5).runsOn(5), isFalse);
      expect(week.toggled(5).toggled(5).isHalfDay(5), isFalse);
    });

    test('a shape can be set without disturbing the rest', () {
      final week = WorkingWeek.fromApiValue(sixDay).withShape(5, WorkingWeek.halfDay);

      expect(week.apiValue, halfSaturday);
      expect(week.withShape(5, WorkingWeek.fullDay).apiValue, sixDay);
    });
  });
}
