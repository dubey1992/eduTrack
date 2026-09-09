import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/classes/presentation/class_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';

Widget wrap(FakeSchoolClassRepository fake) {
  return ProviderScope(
    overrides: [
      schoolClassRepositoryProvider.overrideWithValue(fake),
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
      home: const Scaffold(body: ClassListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no classes', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No classes set up yet.'), findsOneWidget);
  });

  testWidgets('shows a class card with its section', (tester) async {
    await tester.pumpWidget(
      wrap(
        FakeSchoolClassRepository(
          classes: [
            const SchoolClass(
              id: 1,
              schoolId: 1,
              schoolName: 'Sunrise Public School',
              academicYearId: 3,
              academicYearName: '2026-27',
              name: 'Grade 8',
              level: 8,
              sections: [
                ClassSection(
                  id: 1,
                  schoolClassId: 1,
                  name: 'A',
                  roomNumber: 'Room 204',
                  classTeacherId: 9,
                  classTeacherName: 'Priya Sharma',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grade 8'), findsOneWidget);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.textContaining('Priya Sharma'), findsOneWidget);
  });
}
