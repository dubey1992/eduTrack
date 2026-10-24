import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/crew_form_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/crew_list_screen.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attendant_fixtures.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_staff_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/fake_user_repository.dart';
import '../../support/transport_fixtures.dart';

/// Transport > Crew: drivers and attendants as one list, open to the
/// Transport Manager (docs/driver-app.md, D10).
const _transportManager = AuthenticatedUser(
  id: 30,
  name: 'Mohan',
  email: 'mohan@example.com',
  role: UserRole.transportManager,
  schoolId: 1,
);
const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 7, name: 'Asha', email: 'asha@example.com', role: UserRole.teacher, schoolId: 1);

final sureshDriver = StaffProfile(
  id: 41,
  userId: 141,
  employeeId: 'DRV-001',
  firstName: 'Suresh',
  lastName: 'Pawar',
  name: 'Suresh Pawar',
  email: 'attendant-9f8e7d6c5b4a3928@no-email.invalid',
  hasEmail: false,
  mobile: '+91 9822010001',
  role: UserRole.driver,
  status: UserStatus.active,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: null,
  departmentName: null,
  designation: 'Driver',
  joiningDate: DateTime(2026, 4, 1),
  address: null,
  classTeacherOf: const [],
  driverId: 9,
  licenceNumber: 'MH12 20190012345',
  licenceExpiry: '2020-01-01',
);

Widget wrap({
  required FakeStaffRepository staff,
  required FakeTransportRepository transport,
  AuthenticatedUser actor = _schoolAdmin,
}) {
  return ProviderScope(
    overrides: [
      staffRepositoryProvider.overrideWithValue(staff),
      transportRepositoryProvider.overrideWithValue(transport),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: CrewListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('lists drivers and attendants together, each as what they are', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        staff: FakeStaffRepository(staff: [sureshDriver, meeraAttendant]),
        transport: FakeTransportRepository(drivers: const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bus crew'), findsOneWidget);
    expect(find.text('Suresh Pawar'), findsOneWidget);
    expect(find.text('Meera Sharma'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Attendant'), findsOneWidget);
    expect(find.textContaining('MH12 20190012345'), findsOneWidget, reason: "the driver's licence");
    expect(find.text('Licence expired'), findsOneWidget, reason: 'a 2020 expiry, flagged');
  });

  testWidgets('the transport manager can add crew, and open their sign-in', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        staff: FakeStaffRepository(staff: [sureshDriver]),
        transport: FakeTransportRepository(drivers: const []),
        actor: _transportManager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-crew')), findsOneWidget);
    expect(find.byKey(const Key('crew-sign-in-41')), findsOneWidget);
    expect(find.byKey(const Key('crew-edit-41')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-crew')));
    await tester.pumpAndSettle();
    expect(find.byType(CrewFormDialog), findsOneWidget);
  });

  testWidgets('a teacher reads nothing of it and cannot add', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        staff: FakeStaffRepository(staff: [sureshDriver]),
        transport: FakeTransportRepository(drivers: const []),
        actor: _teacher,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-crew')), findsNothing);
    expect(find.byKey(const Key('crew-sign-in-41')), findsNothing);
  });

  testWidgets('adding a driver sends the role, the mobile and the licence, and lands in the list', (tester) async {
    useDesktop(tester);
    final staff = FakeStaffRepository(staff: []);
    await tester.pumpWidget(
      wrap(
        staff: staff,
        transport: FakeTransportRepository(drivers: const []),
        actor: _transportManager,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No drivers or attendants yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-crew')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('crew-first-name')), 'Suresh');
    await tester.enterText(find.byKey(const Key('crew-last-name')), 'Pawar');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mobile'), '9822010001');
    await tester.enterText(find.byKey(const Key('crew-employee-id')), 'DRV-001');
    await tester.enterText(find.byKey(const Key('crew-licence-number')), 'MH12 20190012345');
    await tester.tap(find.byKey(const Key('crew-save')));
    await tester.pumpAndSettle();

    expect(staff.lastCreate!['role'], UserRole.driver);
    expect(staff.lastCreate!['password'], isNull);
    expect(staff.lastCreate!['licence_number'], 'MH12 20190012345');
    expect(find.byType(CrewFormDialog), findsNothing);
    expect(find.textContaining('Driver added.'), findsOneWidget);
    expect(find.text('Suresh Pawar'), findsOneWidget);
  });

  testWidgets('an attendant needs no licence', (tester) async {
    useDesktop(tester);
    final staff = FakeStaffRepository(staff: []);
    await tester.pumpWidget(
      wrap(
        staff: staff,
        transport: FakeTransportRepository(drivers: const []),
        actor: _transportManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-crew')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crew-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendant').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crew-licence-number')), findsNothing);

    await tester.enterText(find.byKey(const Key('crew-first-name')), 'Meera');
    await tester.enterText(find.byKey(const Key('crew-last-name')), 'Sharma');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mobile'), '9876543210');
    await tester.enterText(find.byKey(const Key('crew-employee-id')), 'ATT-001');
    await tester.tap(find.byKey(const Key('crew-save')));
    await tester.pumpAndSettle();

    expect(staff.lastCreate!['role'], UserRole.busAttendant);
    expect(staff.lastCreate!['licence_number'], isNull);
  });

  testWidgets('driver records from before drivers could sign in are listed apart, to be linked', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        staff: FakeStaffRepository(staff: [sureshDriver]),
        // sanjay has no staff member behind him; a record only.
        transport: FakeTransportRepository(drivers: const [sanjay]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unlinked-drivers')), findsOneWidget);
    expect(find.textContaining('Sanjay Patel'), findsOneWidget);
  });
}
