import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:edutrack_app/features/timetable/presentation/timetable_screen.dart';
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

Widget wrap(AuthenticatedUser actor) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository()),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository()),
      periodRepositoryProvider.overrideWithValue(FakePeriodRepository()),
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository()),
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
}
