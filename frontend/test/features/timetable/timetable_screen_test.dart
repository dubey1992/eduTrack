import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/timetable/data/models/period.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:edutrack_app/features/timetable/presentation/timetable_screen.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/edit_entry_dialog.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/manage_periods_dialog.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_period_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/fake_timetable_repository.dart';
import '../../support/fake_user_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 5, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: 9, classTeacherName: 'Admin'),
  ],
);

const _period = Period(id: 1, schoolId: 1, periodNumber: 1, startTime: '08:30', endTime: '09:15');

Widget wrap(
  AuthenticatedUser actor, {
  FakeSchoolClassRepository? schoolClasses,
  FakePeriodRepository? periods,
  FakeTimetableRepository? timetable,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      schoolClassRepositoryProvider.overrideWithValue(schoolClasses ?? FakeSchoolClassRepository()),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository()),
      periodRepositoryProvider.overrideWithValue(periods ?? FakePeriodRepository()),
      timetableRepositoryProvider.overrideWithValue(timetable ?? FakeTimetableRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TimetableScreen()),
    ),
  );
}

void main() {
  testWidgets('a school admin sees the admin controls (class picker, manage periods)', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Class schedules and period management.'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Class'), findsOneWidget);
    expect(find.text('Manage Periods'), findsOneWidget);
    expect(find.text('Pick a class section to view its timetable.'), findsOneWidget);
  });

  testWidgets('a teacher sees their own read-only schedule with no admin controls', (tester) async {
    await tester.pumpWidget(wrap(_teacher));
    await tester.pumpAndSettle();

    expect(find.text('Your weekly teaching schedule.'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Class'), findsNothing);
    expect(find.text('Manage Periods'), findsNothing);
    expect(find.text('No periods assigned to you yet.'), findsOneWidget);
  });

  testWidgets('tapping an empty grid cell opens EditEntryDialog in create mode', (tester) async {
    await tester.pumpWidget(
      wrap(
        _schoolAdmin,
        schoolClasses: FakeSchoolClassRepository(classes: [_schoolClass]),
        periods: FakePeriodRepository(periods: [_period]),
        timetable: FakeTimetableRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    // Every cell in the (empty) grid is unassigned, so shows an add icon.
    expect(find.byIcon(Icons.add), findsWidgets);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.byType(EditEntryDialog), findsOneWidget);
    // No entry behind this cell, so it's create mode - no Clear button.
    expect(find.widgetWithText(TextButton, 'Clear'), findsNothing);
  });

  testWidgets('tapping Manage Periods opens ManagePeriodsDialog', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manage Periods'));
    await tester.pumpAndSettle();

    expect(find.byType(ManagePeriodsDialog), findsOneWidget);
    expect(find.widgetWithText(AlertDialog, 'Manage Periods'), findsOneWidget);
  });
}
