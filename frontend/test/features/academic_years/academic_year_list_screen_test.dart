import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/academic_years/presentation/academic_year_list_screen.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';

Widget wrap(FakeAcademicYearRepository fake) {
  return ProviderScope(
    overrides: [
      academicYearRepositoryProvider.overrideWithValue(fake),
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
      home: const Scaffold(body: AcademicYearListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no academic years', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No academic years set up yet.'), findsOneWidget);
  });

  testWidgets('shows the current-year badge for an academic year', (tester) async {
    await tester.pumpWidget(
      wrap(
        FakeAcademicYearRepository(
          years: [
            AcademicYear(
              id: 1,
              schoolId: 1,
              schoolName: 'Sunrise Public School',
              name: '2026-27',
              startDate: DateTime(2026, 4, 1),
              endDate: DateTime(2027, 3, 31),
              isCurrent: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026-27'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
  });
}
