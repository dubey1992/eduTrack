import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:edutrack_app/features/today/presentation/week_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_timetable_repository.dart';
import '../../support/session_users.dart';

/// "My week" in the School365ai app (docs/mobile-apps-review.md, 7.5).
TimetableEntry _entry(
  int id,
  DayOfWeek day,
  int period,
  String start,
  String subject, {
  int teacherId = 1,
  String shape = WorkingWeek.fullDay,
}) => TimetableEntry(
  id: id,
  schoolId: 1,
  classSectionId: 10,
  classSectionName: 'Grade 8 A',
  periodId: period,
  periodNumber: period,
  dayOfWeek: day,
  periodDayShape: shape,
  periodStartTime: start,
  periodEndTime: start,
  subjectId: 3,
  subjectName: subject,
  teacherId: teacherId,
  teacherName: 'Asha Rao',
);

void main() {
  Future<FakeTimetableRepository> show(WidgetTester tester, List<TimetableEntry> entries) async {
    final repository = FakeTimetableRepository(entries: entries);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Asha Rao')),
          ),
        ],
        // Wednesday 18 November 2026.
        child: MaterialApp(
          theme: AppTheme.teacherLight(),
          home: WeekScreen(today: DateTime(2026, 11, 18)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets("opens on today with today's periods in bell order, and only the teacher's own", (tester) async {
    await show(tester, [
      _entry(1, DayOfWeek.wednesday, 3, '10:30', 'Physics'),
      _entry(2, DayOfWeek.wednesday, 1, '08:30', 'Mathematics'),
      _entry(3, DayOfWeek.monday, 2, '09:30', 'Chemistry'),
      _entry(4, DayOfWeek.wednesday, 2, '09:30', 'History', teacherId: 99),
    ]);

    expect(find.text('Wed (today)'), findsOneWidget);
    expect(find.text('Wednesday: 2 periods'), findsOneWidget);
    expect(find.text('History'), findsNothing);
    expect(tester.getTopLeft(find.text('Mathematics')).dy, lessThan(tester.getTopLeft(find.text('Physics')).dy));
  });

  testWidgets('another day is one tap', (tester) async {
    await show(tester, [
      _entry(1, DayOfWeek.wednesday, 1, '08:30', 'Physics'),
      _entry(2, DayOfWeek.monday, 2, '09:30', 'Chemistry'),
    ]);

    await tester.tap(find.byKey(const Key('week-day-monday')));
    await tester.pumpAndSettle();

    expect(find.text('Monday: 1 period'), findsOneWidget);
    expect(find.text('Chemistry'), findsOneWidget);
    expect(find.text('Physics'), findsNothing);
  });

  testWidgets('a half-day set of periods shows only on a day with nothing else', (tester) async {
    await show(tester, [
      _entry(1, DayOfWeek.wednesday, 1, '08:30', 'Physics'),
      _entry(2, DayOfWeek.wednesday, 1, '08:00', 'Short Physics', shape: WorkingWeek.halfDay),
      _entry(3, DayOfWeek.saturday, 1, '08:00', 'Saturday Maths', shape: WorkingWeek.halfDay),
    ]);

    expect(find.text('Short Physics'), findsNothing);

    await tester.tap(find.byKey(const Key('week-day-saturday')));
    await tester.pumpAndSettle();
    expect(find.text('Saturday Maths'), findsOneWidget);
  });

  testWidgets('with no periods at all it says who sets them', (tester) async {
    await show(tester, const []);

    expect(find.byKey(const Key('week-empty')), findsOneWidget);
  });
}
