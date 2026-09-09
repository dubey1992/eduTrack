import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/departments/presentation/department_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';

Widget wrap(FakeDepartmentRepository fake) {
  return ProviderScope(
    overrides: [
      departmentRepositoryProvider.overrideWithValue(fake),
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
    await tester.pumpWidget(
      wrap(
        FakeDepartmentRepository(
          departments: [
            const Department(
              id: 1,
              schoolId: 1,
              schoolName: 'Sunrise Public School',
              name: 'Mathematics',
              hodUserId: 5,
              hodName: 'Priya Sharma',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('HOD: Priya Sharma'), findsOneWidget);
  });
}
