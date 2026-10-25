import 'package:edutrack_app/features/today/data/models/teacher_day.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server's answer, field for field as backend-python/school/today.py
/// writes it.
void main() {
  final json = <String, dynamic>{
    'date': '2026-10-26',
    'weekday': 'monday',
    'now': '10:15',
    'school_day': {'is_open': true, 'shape': 'half', 'holiday': null},
    'periods': [
      {
        'timetable_entry_id': 11,
        'period_id': 1,
        'period_number': 1,
        'start_time': '09:00',
        'end_time': '09:45',
        'state': 'done',
        'class_section_id': 81,
        'class_section': 'Grade 8 A',
        'subject_id': 4,
        'subject': 'Mathematics',
        'report': {'filed': true, 'id': 501},
      },
      {
        'timetable_entry_id': 13,
        'period_id': 3,
        'period_number': 3,
        'start_time': '11:00',
        'end_time': '11:45',
        'state': 'upcoming',
        'class_section_id': 91,
        'class_section': 'Grade 9 A',
        'subject_id': 5,
        'subject': 'Science',
        'report': {'filed': false, 'id': null},
      },
    ],
    'registers': [
      {'class_section_id': 81, 'class_section': 'Grade 8 A', 'submitted': false},
    ],
    'leave': {
      'today': null,
      'this_week': [
        {'id': 7, 'leave_type': 'medical', 'start_date': '2026-10-29', 'end_date': '2026-10-30'},
      ],
    },
    'owed': {'reports': 0, 'registers': 1},
  };

  test('reads every part of the day', () {
    final day = TeacherDay.fromJson(json);

    expect(day.date, DateTime(2026, 10, 26));
    expect((day.isOpen, day.isHalfDay, day.holidayName, day.now), (true, true, null, '10:15'));
    expect(day.periods.map((p) => (p.periodNumber, p.state, p.reportFiled, p.reportId)), [
      (1, PeriodState.done, true, 501),
      (3, PeriodState.upcoming, false, null),
    ]);
    expect(day.registers.single.submitted, isFalse);
    expect(day.leaveToday, isNull);
    expect(day.otherLeaveThisWeek.single.endDate, DateTime(2026, 10, 30));
    expect((day.reportsOwed, day.registersOwed, day.owed), (0, 1, 1));
  });

  test('a holiday carries its name and nothing else', () {
    final day = TeacherDay.fromJson({
      ...json,
      'school_day': {
        'is_open': false,
        'shape': 'full',
        'holiday': {'id': 3, 'name': 'Diwali', 'type': 'religious'},
      },
      'periods': <dynamic>[],
      'registers': <dynamic>[],
      'owed': {'reports': 0, 'registers': 0},
    });

    expect((day.isOpen, day.holidayName, day.owed), (false, 'Diwali', 0));
    expect(day.periods, isEmpty);
  });

  test('a report is owed only once its period has begun', () {
    final day = TeacherDay.fromJson(json);
    final upcoming = day.periods.last;

    expect(upcoming.reportFiled, isFalse);
    expect(upcoming.reportOwed, isFalse);
  });

  test('an unknown period state reads as upcoming rather than failing the day', () {
    expect(PeriodState.fromApiValue('later'), PeriodState.upcoming);
  });
}
