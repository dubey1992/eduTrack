import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/application/student_list_notifier.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/add_student_dialog.dart';
import 'package:edutrack_app/features/students/presentation/edit_student_dialog.dart';
import 'package:edutrack_app/features/students/presentation/student_list_screen.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _walker = Student(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 10,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'STU-0042',
  firstName: 'Arjun',
  lastName: 'Kumar',
  name: 'Arjun Kumar',
  rollNumber: '1',
  guardianName: 'Raj Kumar',
  guardianMobile: null,
  address: null,
  status: StudentStatus.active,
);

const _rider = Student(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 10,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'STU-0043',
  firstName: 'Aarav',
  lastName: 'Mehta',
  name: 'Aarav Mehta',
  rollNumber: '2',
  guardianName: 'Neha Mehta',
  guardianMobile: null,
  address: null,
  status: StudentStatus.active,
  transport: StudentTransport(
    routeId: 1,
    routeName: 'Green Park',
    routeLabel: 'Bus 04 - Green Park',
    vehicleName: 'Bus 04',
    stopId: 101,
    stopName: 'Lake View',
  ),
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
    ClassSection(id: 10, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

Widget wrap(Widget home, FakeStudentRepository students, FakeTransportRepository transport) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(students),
      transportRepositoryProvider.overrideWithValue(transport),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );
}

Widget dialogHost(Widget Function() dialog) {
  return Scaffold(
    body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showDialog(context: context, builder: (_) => dialog()),
        child: const Text('Open'),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('StudentListNotifier transport', () {
    test('createStudent() assigns transport after admission when a route is picked', () async {
      final students = FakeStudentRepository();
      final container = ProviderContainer(
        overrides: [studentRepositoryProvider.overrideWithValue(students)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      await container.read(studentListNotifierProvider.future);

      await container
          .read(studentListNotifierProvider.notifier)
          .createStudent(
            classSectionId: 10,
            admissionNumber: 'STU-1',
            firstName: 'Sara',
            lastName: 'Ali',
            guardianName: 'Ali',
            routeId: 1,
            stopId: 101,
          );

      expect(students.lastTransportCall, {'student_id': 1, 'route_id': 1, 'stop_id': 101});
      expect(container.read(studentListNotifierProvider).value!.items.single.transport?.stopName, 'Lake View');
    });

    test('createStudent() without a route never calls the transport endpoint', () async {
      final students = FakeStudentRepository();
      final container = ProviderContainer(overrides: [studentRepositoryProvider.overrideWithValue(students)]);
      addTearDown(container.dispose);
      await container.read(studentListNotifierProvider.future);

      await container
          .read(studentListNotifierProvider.notifier)
          .createStudent(
            classSectionId: 10,
            admissionNumber: 'STU-1',
            firstName: 'S',
            lastName: 'A',
            guardianName: 'G',
          );

      expect(students.lastTransportCall, isNull);
    });

    test('updateStudent() only touches transport when the selection changed, and can clear it', () async {
      final students = FakeStudentRepository(students: [_rider]);
      final container = ProviderContainer(overrides: [studentRepositoryProvider.overrideWithValue(students)]);
      addTearDown(container.dispose);
      await container.read(studentListNotifierProvider.future);
      final notifier = container.read(studentListNotifierProvider.notifier);

      await notifier.updateStudent(_rider, guardianName: 'Neha M.', routeId: 1, stopId: 101);
      expect(students.lastTransportCall, isNull);

      await notifier.updateStudent(_rider, guardianName: 'Neha M.', routeId: 1, stopId: 102);
      expect(students.lastTransportCall!['stop_id'], 102);
      expect(container.read(studentListNotifierProvider).value!.items.single.transport?.stopName, 'Central Park');

      await notifier.updateStudent(_rider, guardianName: 'Neha M.', routeId: null, stopId: null);
      expect(students.lastTransportCall!['route_id'], isNull);
      expect(container.read(studentListNotifierProvider).value!.items.single.transport, isNull);
    });

    test('a capacity failure on assignment surfaces after the student is admitted', () async {
      final students = FakeStudentRepository(
        failSetTransportWith: const Failure(code: 'ROUTE_CAPACITY_FULL', message: 'Bus 04 - Green Park is full.'),
      );
      final container = ProviderContainer(
        overrides: [studentRepositoryProvider.overrideWithValue(students)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      await container.read(studentListNotifierProvider.future);

      await expectLater(
        container
            .read(studentListNotifierProvider.notifier)
            .createStudent(
              classSectionId: 10,
              admissionNumber: 'STU-1',
              firstName: 'S',
              lastName: 'A',
              guardianName: 'G',
              routeId: 1,
              stopId: 101,
            ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'ROUTE_CAPACITY_FULL')),
      );
      expect(students.students, hasLength(1));
      expect(container.read(studentListNotifierProvider).value!.items.single.transport, isNull);
    });
  });

  group('Students list', () {
    testWidgets('shows a Transport column with the route label and stop, or No Transport', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          const Scaffold(body: StudentListScreen()),
          FakeStudentRepository(students: [_walker, _rider]),
          FakeTransportRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('No Transport'), findsOneWidget);
      expect(find.text('Bus 04 - Green Park (Lake View)'), findsOneWidget);
    });
  });

  group('Student dialogs', () {
    testWidgets('Add Student offers No Transport, then the route\'s stops once a route is picked', (tester) async {
      final students = FakeStudentRepository();
      final transport = FakeTransportRepository(routes: [greenPark, lakeRoadNoVehicle]);
      await tester.pumpWidget(wrap(dialogHost(() => const AddStudentDialog()), students, transport));
      useDesktop(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('No Transport'), findsOneWidget);
      expect(find.widgetWithText(DropdownButtonFormField<int>, 'Stop'), findsNothing);

      await tester.ensureVisible(find.text('No Transport'));
      await tester.tap(find.text('No Transport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bus 04 - Green Park').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(DropdownButtonFormField<int>, 'Stop'), findsOneWidget);
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Lake View').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Sara');
      await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Ali');
      await tester.enterText(find.widgetWithText(TextFormField, 'Admission ID'), 'STU-9');
      await tester.enterText(find.widgetWithText(TextFormField, 'Parent / Guardian'), 'Ali');
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grade 8 A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Student'));
      await tester.pumpAndSettle();

      expect(students.lastTransportCall, {'student_id': 1, 'route_id': 1, 'stop_id': 101});
      expect(find.text('Student admitted.'), findsOneWidget);
    });

    testWidgets('Add Student refuses to save a route without a stop', (tester) async {
      final students = FakeStudentRepository();
      await tester.pumpWidget(
        wrap(dialogHost(() => const AddStudentDialog()), students, FakeTransportRepository(routes: [greenPark])),
      );
      useDesktop(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('No Transport'));
      await tester.tap(find.text('No Transport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bus 04 - Green Park').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Student'));
      await tester.pumpAndSettle();

      expect(find.text('Pick a stop for this route'), findsOneWidget);
      expect(students.lastTransportCall, isNull);
    });

    testWidgets('Edit Student pre-selects the current route and stop and can switch to No Transport', (tester) async {
      final students = FakeStudentRepository(students: [_rider]);
      await tester.pumpWidget(
        wrap(
          dialogHost(() => const EditStudentDialog(student: _rider)),
          students,
          FakeTransportRepository(routes: [greenPark]),
        ),
      );
      useDesktop(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Bus 04 - Green Park'), findsOneWidget);
      expect(find.text('1. Lake View'), findsOneWidget);

      await tester.ensureVisible(find.text('Bus 04 - Green Park'));
      await tester.tap(find.text('Bus 04 - Green Park'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No Transport').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(students.lastTransportCall, {'student_id': 2, 'route_id': null, 'stop_id': null});
      expect(find.text('Student updated.'), findsOneWidget);
    });

    testWidgets('Edit Student keeps a now-inactive route visible as "(inactive)"', (tester) async {
      final students = FakeStudentRepository(students: [_rider]);
      await tester.pumpWidget(
        wrap(dialogHost(() => const EditStudentDialog(student: _rider)), students, FakeTransportRepository()),
      );
      useDesktop(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Bus 04 - Green Park (inactive)'), findsOneWidget);
    });
  });
}
