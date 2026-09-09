import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/staff/presentation/staff_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

Widget wrap(FakeStaffRepository fake) {
  return ProviderScope(
    overrides: [
      staffRepositoryProvider.overrideWithValue(fake),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
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

    await tester.enterText(find.widgetWithText(TextField, 'Search employee'), 'Priya');
    await tester.pumpAndSettle();

    expect(find.textContaining('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('Rahul Verma'), findsNothing);
  });
}
