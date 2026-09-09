import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/departments/presentation/department_list_screen.dart';
import 'package:edutrack_app/features/departments/presentation/edit_department_dialog.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_user_repository.dart';

const _department = Department(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: 5,
  hodName: 'Priya Sharma',
);

const _hod = AppUser(
  id: 5,
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya.sharma@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
);

Widget wrap(FakeDepartmentRepository fake) {
  return ProviderScope(
    overrides: [
      departmentRepositoryProvider.overrideWithValue(fake),
      userRepositoryProvider.overrideWithValue(FakeUserRepository(users: const [_hod])),
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
      home: const Scaffold(body: DepartmentListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no departments', (tester) async {
    await tester.pumpWidget(wrap(FakeDepartmentRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No departments set up yet.'), findsOneWidget);
  });

  testWidgets('shows a department card with its HOD', (tester) async {
    await tester.pumpWidget(wrap(FakeDepartmentRepository(departments: [_department])));
    await tester.pumpAndSettle();

    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('HOD: Priya Sharma'), findsOneWidget);
  });

  testWidgets('tapping the edit action opens the edit dialog for that row', (tester) async {
    await tester.pumpWidget(wrap(FakeDepartmentRepository(departments: [_department])));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(EditDepartmentDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Department name'), findsOneWidget);
  });

  testWidgets('confirming the delete action removes the row and shows confirmation', (tester) async {
    final fake = FakeDepartmentRepository(departments: [_department]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete department?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await fake.list(), isEmpty);
    expect(find.text('No departments set up yet.'), findsOneWidget);
    expect(find.text('Mathematics was deleted.'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation leaves the row untouched', (tester) async {
    final fake = FakeDepartmentRepository(departments: [_department]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await fake.list(), hasLength(1));
    expect(find.text('Mathematics'), findsOneWidget);
  });

  testWidgets('shows the error state with a retry button when loading fails', (tester) async {
    final fake = FakeDepartmentRepository(
      failListPageWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load departments.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load departments.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No departments set up yet.'), findsOneWidget);
  });
}
