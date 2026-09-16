import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/staff/presentation/edit_staff_profile_dialog.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/staff/presentation/staff_list_screen.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_staff_repository.dart';
import '../../support/fake_user_repository.dart';

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

// Matches _teacher.departmentId (1) - the edit dialog's department picker
// asserts its initialValue matches exactly one item, so the picker's data
// source must already contain the profile's current department.
const _mathematicsDepartment = Department(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

Widget wrap(FakeStaffRepository fake, {FakeUserRepository? userRepositoryFake}) {
  return ProviderScope(
    overrides: [
      staffRepositoryProvider.overrideWithValue(fake),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository(departments: [_mathematicsDepartment])),
      userRepositoryProvider.overrideWithValue(userRepositoryFake ?? FakeUserRepository()),
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
      home: const Scaffold(body: StaffListScreen()),
    ),
  );
}

/// Types into the search box and waits out the debounce.
///
/// pumpAndSettle alone is not enough: while the debounce timer counts down
/// nothing has a frame scheduled, so it returns before the timer fires.
Future<void> _search(WidgetTester tester, String term) async {
  await tester.enterText(find.widgetWithText(TextField, 'Search employee'), term);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state when there is no staff yet', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No teachers or staff added yet.'), findsOneWidget);
  });

  testWidgets('shows an employee with their department and assigned classes', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [_teacher])));
    await tester.pumpAndSettle();

    expect(find.textContaining('TCH-012'), findsOneWidget);
    expect(find.textContaining('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('Mathematics'), findsOneWidget);
    expect(find.textContaining('Grade 8 A'), findsOneWidget);
  });

  testWidgets('filtering by search hides non-matching employees', (tester) async {
    await tester.pumpWidget(
      wrap(
        FakeStaffRepository(
          staff: [
            _teacher,
            StaffProfile(
              id: 2,
              userId: 2,
              employeeId: 'TCH-018',
              firstName: 'Rahul',
              lastName: 'Verma',
              name: 'Rahul Verma',
              email: 'rahul@example.com',
              mobile: null,
              role: UserRole.teacher,
              status: UserStatus.active,
              schoolId: 1,
              schoolName: 'Sunrise Public School',
              departmentId: null,
              departmentName: null,
              designation: null,
              joiningDate: DateTime(2024, 6, 1),
              address: null,
              classTeacherOf: const [],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('Rahul Verma'), findsOneWidget);

    await _search(tester, 'Priya');

    expect(find.textContaining('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('Rahul Verma'), findsNothing);
  });

  testWidgets('searching keeps the search box on screen, with what was typed in it', (tester) async {
    // The filters used to be drawn inside the list's AsyncValueView, so a
    // search tore them down and rebuilt them - losing the keyboard focus
    // mid-word - and a search that matched nobody removed the box entirely,
    // leaving no way to undo the search that had emptied the screen.
    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [_teacher])));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Search employee');
    await tester.enterText(field, 'Nobody at all');

    // While the request is in flight.
    await tester.pump(const Duration(milliseconds: 500));
    expect(field, findsOneWidget);

    await tester.pumpAndSettle();

    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Nobody at all');
    expect(find.text('No employees match these filters.'), findsOneWidget);
    expect(find.text('No teachers or staff added yet.'), findsNothing);
  });

  testWidgets('an empty list with nothing searched says nobody has been added', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No teachers or staff added yet.'), findsOneWidget);
    expect(find.text('No employees match these filters.'), findsNothing);
  });

  testWidgets('tapping Edit on a row opens the edit dialog for that employee', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [_teacher])));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(EditStaffProfileDialog), findsOneWidget);
    expect(find.text('Edit Priya Sharma'), findsOneWidget);
  });

  testWidgets('tapping Deactivate updates the row status badge', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final userRepositoryFake = FakeUserRepository(
      users: [
        const AppUser(
          id: 1,
          firstName: 'Priya',
          lastName: 'Sharma',
          name: 'Priya Sharma',
          email: 'priya.sharma@example.com',
          mobile: '9876543210',
          role: UserRole.teacher,
          status: UserStatus.active,
        ),
      ],
    );
    await tester.pumpWidget(wrap(FakeStaffRepository(staff: [_teacher]), userRepositoryFake: userRepositoryFake));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(StatusBadge, 'Active'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Deactivate'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(StatusBadge, 'Inactive'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Activate'), findsOneWidget);
  });

  testWidgets('shows an error state with a retry button when the repository throws', (tester) async {
    final fake = FakeStaffRepository(
      failListPageWith: const Failure(code: 'STAFF_LIST_FAILED', message: 'Could not load staff.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load staff.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No teachers or staff added yet.'), findsOneWidget);
  });
}
