import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/models/student_class_group.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/application/student_list_notifier.dart';
import 'package:edutrack_app/features/students/presentation/add_student_dialog.dart';
import 'package:edutrack_app/features/students/presentation/student_list_screen.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/fake_transport_repository.dart';

/// The Students page by class and section (docs/onboarding.md, slice O2).

Student _student(int id, String first, {required int sectionId, String? roll}) => Student(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: sectionId,
  classSectionName: 'Class',
  admissionNumber: 'ADM-$id',
  firstName: first,
  lastName: 'K',
  name: '$first K',
  rollNumber: roll,
  guardianName: 'Guardian',
  guardianMobile: null,
  address: null,
  status: StudentStatus.active,
);

const _groups = [
  StudentClassGroup(
    id: 1,
    name: 'Nursery',
    level: -2,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    academicYearName: '2026-27',
    sections: [StudentSectionCount(id: 10, name: 'A', students: 1)],
  ),
  StudentClassGroup(
    id: 2,
    name: 'Class 5',
    level: 5,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    academicYearName: '2026-27',
    sections: [
      StudentSectionCount(id: 20, name: 'A', students: 2),
      StudentSectionCount(id: 21, name: 'B', students: 0),
    ],
  ),
];

FakeStudentRepository _fake({Map<String, Failure> failWith = const {}}) => FakeStudentRepository(
  students: [
    _student(1, 'Tara', sectionId: 10, roll: '1'),
    _student(2, 'Ishan', sectionId: 20, roll: '1'),
    _student(3, 'Zoya', sectionId: 20, roll: '2'),
  ],
  classGroups: _groups,
  failWith: failWith,
);

Widget wrap(FakeStudentRepository fake, {UserRole role = UserRole.schoolAdmin}) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(fake),
      transportRepositoryProvider.overrideWithValue(FakeTransportRepository()),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 1, name: 'Admin', email: 'admin@example.com', role: role),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StudentListScreen()),
    ),
  );
}

void _screen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pickFromDropdown(WidgetTester tester, String item) async {
  await tester.tap(find.byType(DropdownButtonFormField<int?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  group('on a wide screen', () {
    testWidgets('the classes are listed down the side in class order with counts', (tester) async {
      _screen(tester, 1700);
      await tester.pumpWidget(wrap(_fake()));
      await tester.pumpAndSettle();

      final nursery = tester.getTopLeft(find.text('Nursery')).dy;
      final classFive = tester.getTopLeft(find.text('Class 5')).dy;
      expect(nursery, lessThan(classFive));
      expect(find.text('All students'), findsOneWidget);
      expect(find.text('Section B'), findsOneWidget);
    });

    testWidgets('choosing a section shows its students and says they are in roll order', (tester) async {
      _screen(tester, 1700);
      final fake = _fake();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Section A').last);
      await tester.pumpAndSettle();

      expect(fake.sectionCalls.last, 20);
      expect(find.text('Class 5 - A · in roll number order'), findsOneWidget);
      expect(find.textContaining('Tara'), findsNothing);
      expect(find.text('Ishan K'), findsOneWidget);

      await tester.tap(find.text('All students'));
      await tester.pumpAndSettle();
      expect(fake.sectionCalls.last, isNull);
    });

    testWidgets('an empty section says so', (tester) async {
      _screen(tester, 1700);
      await tester.pumpWidget(wrap(_fake()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Section B'));
      await tester.pumpAndSettle();

      expect(find.text('No students in Class 5 - B yet.'), findsOneWidget);
      expect(find.byKey(const Key('renumber-section')), findsNothing);
    });

    testWidgets('a section picked while empty offers Renumber once students are added to it', (tester) async {
      _screen(tester, 1700);
      final fake = _fake();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Section B'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('renumber-section')), findsNothing);

      // What saving the Add Student form does: the student is created and
      // the roll is fetched again.
      await fake.create(
        classSectionId: 21,
        admissionNumber: 'ADM-9',
        firstName: 'Meera',
        lastName: 'K',
        guardianName: 'Guardian',
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(StudentListScreen)));
      await container.read(studentListNotifierProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('renumber-section')), findsOneWidget);
    });

    testWidgets('Add Student starts in the section on screen', (tester) async {
      _screen(tester, 1700);
      await tester.pumpWidget(wrap(_fake()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Section B'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      expect(tester.widget<AddStudentDialog>(find.byType(AddStudentDialog)).classSectionId, 21);
    });

    testWidgets('Add Student from All students starts with no class chosen', (tester) async {
      _screen(tester, 1700);
      await tester.pumpWidget(wrap(_fake()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      expect(tester.widget<AddStudentDialog>(find.byType(AddStudentDialog)).classSectionId, isNull);
    });
  });

  group('on a smaller screen', () {
    testWidgets('a dropdown offers the same sections, in class order', (tester) async {
      _screen(tester, 1300);
      final fake = _fake();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      final nursery = tester.getTopLeft(find.text('Nursery (1)').last).dy;
      final classFiveA = tester.getTopLeft(find.text('Class 5 - A (2)').last).dy;
      expect(nursery, lessThan(classFiveA));

      await tester.tap(find.text('Class 5 - A (2)').last);
      await tester.pumpAndSettle();
      expect(fake.sectionCalls.last, 20);
    });

    testWidgets('a phone gets the dropdown too', (tester) async {
      _screen(tester, 400);
      final fake = _fake();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await _pickFromDropdown(tester, 'Nursery (1)');

      expect(fake.sectionCalls.last, 10);
      expect(find.textContaining('Roll 1 · Tara K'), findsOneWidget);
    });
  });

  group('Renumber A-Z', () {
    Future<void> openSection(WidgetTester tester, FakeStudentRepository fake) async {
      _screen(tester, 1300);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await _pickFromDropdown(tester, 'Class 5 - A (2)');
    }

    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      final fake = _fake();
      await openSection(tester, fake);

      await tester.tap(find.byKey(const Key('renumber-section')));
      await tester.pumpAndSettle();

      expect(find.text('Renumber Class 5 - A?'), findsOneWidget);
      expect(find.textContaining('roll numbers 1 to 2 in alphabetical order'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.renumberCalls, isEmpty);
    });

    testWidgets('confirmed, it renumbers the section and says so', (tester) async {
      final fake = _fake();
      await openSection(tester, fake);

      await tester.tap(find.byKey(const Key('renumber-section')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Renumber'));
      await tester.pumpAndSettle();

      expect(fake.renumberCalls, [20]);
      expect(find.text('Renumbered 2 students of Class 5 - A.'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown', (tester) async {
      final fake = _fake(
        failWith: {'renumber': const Failure(code: 'FORBIDDEN', message: 'You may not renumber this section.')},
      );
      await openSection(tester, fake);

      await tester.tap(find.byKey(const Key('renumber-section')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Renumber'));
      await tester.pumpAndSettle();

      expect(find.text('You may not renumber this section.'), findsOneWidget);
    });

    testWidgets('a role that may only read the roll gets no Renumber button', (tester) async {
      _screen(tester, 1300);
      await tester.pumpWidget(wrap(_fake(), role: UserRole.accountant));
      await tester.pumpAndSettle();
      await _pickFromDropdown(tester, 'Class 5 - A (2)');

      expect(find.byKey(const Key('renumber-section')), findsNothing);
    });
  });

  testWidgets('the class list failing to load offers a retry, and the roll still shows', (tester) async {
    _screen(tester, 1700);
    final fake = _fake(
      failWith: {'classes': const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.')},
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Ishan K'), findsOneWidget);
  });
}
