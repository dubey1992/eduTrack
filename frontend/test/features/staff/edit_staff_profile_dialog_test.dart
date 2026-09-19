import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/staff/data/attendant_access_repository.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/staff/presentation/edit_staff_profile_dialog.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attendant_fixtures.dart';
import '../../support/fake_attendant_access_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_staff_repository.dart';

final _teacher = StaffProfile(
  id: 1,
  userId: 1,
  employeeId: 'TCH-012',
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya.sharma@example.com',
  mobile: '9876543210',
  role: UserRole.teacher,
  status: UserStatus.active,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: 1,
  departmentName: 'Mathematics',
  designation: null,
  joiningDate: DateTime(2024, 6, 1),
  address: null,
  classTeacherOf: const ['Grade 8 A'],
);

// Matches _teacher.departmentId (1) - the department picker's
// DropdownButtonFormField asserts that its initialValue matches exactly one
// item, so the picker's data source must already contain the profile's
// current department.
const _mathematicsDepartment = Department(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

Widget wrap(FakeStaffRepository fake, {StaffProfile? profile, FakeAttendantAccessRepository? access}) {
  return ProviderScope(
    overrides: [
      staffRepositoryProvider.overrideWithValue(fake),
      attendantAccessRepositoryProvider.overrideWithValue(access ?? FakeAttendantAccessRepository(access: freshAccess)),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: const AuthenticatedUser(
            id: 5,
            name: 'Admin',
            email: 'admin@example.com',
            role: UserRole.schoolAdmin,
          ),
        ),
      ),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository(departments: [_mathematicsDepartment])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditStaffProfileDialog(profile: profile ?? _teacher),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a validation error when the employee ID is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [_teacher])));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Employee ID'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('updates the staff profile, closes the dialog, and shows a confirmation snackbar', (tester) async {
    final fake = FakeStaffRepository(staff: [_teacher]);
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Designation (optional)'), 'Senior Teacher');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list();
    expect(updated.single.designation, 'Senior Teacher');
    expect(find.byType(EditStaffProfileDialog), findsNothing);
    expect(find.text('Staff profile updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open when the repository throws', (tester) async {
    final fake = FakeStaffRepository(
      staff: [_teacher],
      failUpdateWith: const Failure(code: 'STAFF_UPDATE_FAILED', message: 'Could not update the staff profile.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Designation (optional)'), 'Senior Teacher');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not update the staff profile.'), findsOneWidget);
    expect(find.byType(EditStaffProfileDialog), findsOneWidget);
  });

  testWidgets('shows the employee\'s email', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [_teacher])));
    await _openDialog(tester);

    expect(find.text('priya.sharma@example.com'), findsOneWidget);
    expect(find.text('Sign-in & phones'), findsNothing);
  });

  testWidgets('an attendant without an email reads "No email", with a way into their sign-in', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [meeraAttendant]), profile: meeraAttendant));
    await _openDialog(tester);

    expect(find.text('No email'), findsOneWidget);
    expect(find.textContaining('no-email.invalid'), findsNothing);

    await tester.tap(find.text('Sign-in & phones'));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in · Meera Sharma'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
  });
}
