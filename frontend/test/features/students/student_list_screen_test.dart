import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/students/presentation/edit_student_dialog.dart';
import 'package:edutrack_app/features/students/presentation/student_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/fake_transport_repository.dart';

final _student = Student(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 1,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'STU-0042',
  firstName: 'Arjun',
  lastName: 'Kumar',
  name: 'Arjun Kumar',
  rollNumber: '12',
  guardianName: 'Raj Kumar',
  guardianMobile: '9876543210',
  address: null,
  status: StudentStatus.active,
);

final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 1, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

Widget wrap(FakeStudentRepository fake) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(fake),
      transportRepositoryProvider.overrideWithValue(FakeTransportRepository()),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: const AuthenticatedUser(
            id: 1,
            name: 'Admin',
            email: 'admin@example.com',
            role: UserRole.superAdmin,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StudentListScreen()),
    ),
  );
}

/// The row action buttons only render in the desktop DataTable layout (see
/// [Breakpoints.desktop]) - the mobile card layout opens the edit dialog on
/// a plain row tap instead and has no deactivate/activate control at all.
/// Types into the search box and waits out the debounce.
///
/// pumpAndSettle alone is not enough: while the debounce timer counts down
/// nothing has a frame scheduled, so pumpAndSettle returns before it fires.
/// The clock has to be moved on deliberately.
Future<void> _search(WidgetTester tester, String term) async {
  await tester.enterText(find.widgetWithText(TextField, 'Search by name / admission ID'), term);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void _useDesktopLayout(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows an empty state when there are no students', (tester) async {
    await tester.pumpWidget(wrap(FakeStudentRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No students admitted yet.'), findsOneWidget);
  });

  testWidgets('shows a student with their class and guardian', (tester) async {
    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
    await tester.pumpAndSettle();

    expect(find.textContaining('STU-0042'), findsOneWidget);
    expect(find.textContaining('Arjun Kumar'), findsOneWidget);
  });

  testWidgets('filtering by search hides non-matching students', (tester) async {
    final other = Student(
      id: 2,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      classSectionId: 1,
      classSectionName: 'Grade 8 A',
      admissionNumber: 'STU-0043',
      firstName: 'Aarav',
      lastName: 'Mehta',
      name: 'Aarav Mehta',
      rollNumber: '13',
      guardianName: 'Neha Mehta',
      guardianMobile: null,
      address: null,
      status: StudentStatus.active,
    );
    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student, other])));
    await tester.pumpAndSettle();

    await _search(tester, 'Arjun');

    expect(find.textContaining('Arjun Kumar'), findsOneWidget);
    expect(find.textContaining('Aarav Mehta'), findsNothing);
  });

  testWidgets('asks the server once the typing stops, not once per letter', (tester) async {
    // The bug this exists to prevent: wired to onChanged, "Arjun" was five
    // requests, four of them for a prefix nobody wanted - and their replies
    // could arrive in any order.
    final fake = FakeStudentRepository(students: [_student]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    final before = fake.searchCalls.length;
    final field = find.widgetWithText(TextField, 'Search by name / admission ID');

    for (final prefix in ['A', 'Ar', 'Arj', 'Arju', 'Arjun']) {
      await tester.enterText(field, prefix);
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Still nothing: the field has not been quiet long enough.
    expect(fake.searchCalls.length, before);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(fake.searchCalls.length, before + 1);
    expect(fake.searchCalls.last, 'Arjun');
  });

  testWidgets('searches every page, not just the rows on screen', (tester) async {
    // It used to filter the list the screen already held, so a student on any
    // page but this one simply could not be found.
    final many = [
      for (var i = 0; i < 25; i++)
        Student(
          id: 100 + i,
          schoolId: 1,
          schoolName: 'Sunrise Public School',
          classSectionId: 1,
          classSectionName: 'Grade 8 A',
          admissionNumber: 'STU-01$i',
          firstName: 'Filler',
          lastName: '$i',
          name: 'Filler $i',
          rollNumber: '$i',
          guardianName: 'Guardian $i',
          guardianMobile: null,
          address: null,
          status: StudentStatus.active,
        ),
      _student,
    ];

    final fake = FakeStudentRepository(students: many);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    // Page one holds twenty rows; Arjun is not among them.
    expect(find.textContaining('Arjun Kumar'), findsNothing);

    await _search(tester, 'Arjun');

    expect(find.textContaining('Arjun Kumar'), findsOneWidget);
  });

  testWidgets('a search that finds nothing says so, rather than "none admitted"', (tester) async {
    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
    await tester.pumpAndSettle();

    await _search(tester, 'Nobody');

    expect(find.text('No students match this search.'), findsOneWidget);
    expect(find.text('No students admitted yet.'), findsNothing);
  });

  testWidgets('clearing the search brings everyone back at once', (tester) async {
    final fake = FakeStudentRepository(students: [_student]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await _search(tester, 'Nobody');
    expect(find.textContaining('Arjun Kumar'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    // No waiting for the debounce: clearing is the user saying they are done.
    // Null rather than empty - the notifier drops a blank term rather than
    // sending the server a search for nothing.
    expect(fake.searchCalls.last, isNull);
    await tester.pumpAndSettle();
    expect(find.textContaining('Arjun Kumar'), findsOneWidget);
  });

  testWidgets('tapping the row action button opens the edit dialog', (tester) async {
    _useDesktopLayout(tester);

    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pumpAndSettle();

    expect(find.byType(EditStudentDialog), findsOneWidget);
    expect(find.text('Edit Arjun Kumar'), findsOneWidget);
  });

  testWidgets('tapping Deactivate calls the repository and flips the status badge', (tester) async {
    _useDesktopLayout(tester);

    final fake = FakeStudentRepository(students: [_student]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('Arjun Kumar is now inactive.'), findsOneWidget);
    // The action button relabels itself now that the student is inactive.
    expect(find.widgetWithText(TextButton, 'Activate'), findsOneWidget);
  });

  testWidgets('shows an error state with a retry button when loading fails', (tester) async {
    final fake = FakeStudentRepository(
      failListWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load students.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load students.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
