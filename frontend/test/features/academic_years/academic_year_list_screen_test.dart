import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/academic_years/presentation/academic_year_list_screen.dart';
import 'package:edutrack_app/features/academic_years/presentation/edit_academic_year_dialog.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';

final _year = AcademicYear(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: '2026-27',
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: false,
);

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

  testWidgets('tapping the edit action opens the edit dialog for that row', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository(years: [_year])));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(EditAcademicYearDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), findsOneWidget);
    expect(find.text('2026-27'), findsWidgets);
  });

  testWidgets('confirming the delete action removes the row and shows confirmation', (tester) async {
    final fake = FakeAcademicYearRepository(years: [_year]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete academic year?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await fake.list(), isEmpty);
    expect(find.text('No academic years set up yet.'), findsOneWidget);
    expect(find.text('2026-27 was deleted.'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation leaves the row untouched', (tester) async {
    final fake = FakeAcademicYearRepository(years: [_year]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await fake.list(), hasLength(1));
    expect(find.text('2026-27'), findsOneWidget);
  });

  testWidgets('shows the error state with a retry button when loading fails', (tester) async {
    final fake = FakeAcademicYearRepository(
      failListPageWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load academic years.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load academic years.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No academic years set up yet.'), findsOneWidget);
  });
}
