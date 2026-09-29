import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/application/academic_year_picker_provider.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/classes/application/class_section_picker_provider.dart';
import 'package:edutrack_app/features/promotion/application/promotion_notifier.dart';
import 'package:edutrack_app/features/promotion/application/promotion_target_provider.dart';
import 'package:edutrack_app/features/promotion/data/models/promotion_preview.dart';
import 'package:edutrack_app/features/promotion/data/promotion_repository.dart';
import 'package:edutrack_app/features/promotion/presentation/promotion_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_promotion_repository.dart';
import '../../support/session_users.dart';

/// The promotion wizard on screen (docs/promotion.md): two steps, a decision
/// per student, and nothing written by either.
final _sections = [
  const ClassSectionOption(id: 10, label: 'Grade 8 A'),
  const ClassSectionOption(id: 11, label: 'Grade 8 B'),
];

AcademicYear year(int id, String name) => AcademicYear(
  id: id,
  schoolId: 1,
  schoolName: 'Green Valley',
  name: name,
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: id == 1,
);

Widget wrap(FakePromotionRepository fake, {UserRole role = UserRole.schoolAdmin}) {
  return ProviderScope(
    overrides: [
      promotionRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
      classSectionPickerProvider.overrideWith((ref, arg) async => _sections),
      academicYearPickerProvider.overrideWith((ref, arg) async => [year(1, '2026-27'), year(2, '2027-28')]),
      promotionTargetSectionsProvider.overrideWith(
        (ref, arg) async => arg == null ? const [] : [const ClassSectionOption(id: 20, label: 'Grade 9 A')],
      ),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: PromotionScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(2200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Picks a class and a year, then asks for the roster.
Future<void> review(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('promotion-source')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Grade 8 A').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('promotion-year')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('2027-28').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, 'Review students'));
  await tester.pumpAndSettle();
}

void main() {
  group('choosing what to promote', () {
    testWidgets('offers the class, the year and an optional target', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Class to promote'), findsOneWidget);
      expect(find.text('Into academic year'), findsOneWidget);
      expect(find.text('Suggest one for me'), findsOneWidget);
    });

    testWidgets('will not ask for a roster before it knows the class and the year', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Review students')).onPressed, isNull);
    });

    testWidgets('shows the roster once both are chosen', (tester) async {
      useDesktop(tester);
      final fake = FakePromotionRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await review(tester);

      expect(fake.lastCall, {'class_section_id': 10, 'to_academic_year_id': 2, 'to_class_section_id': null});
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Bina Kapoor'), findsOneWidget);
    });

    testWidgets('a server that refuses is shown with a way to try again', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository(failure: Failure.network())));
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    });
  });

  group('reading the roster', () {
    testWidgets('names both sides of the move and says when the target was a guess', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.text('Grade 8 A'), findsWidgets);
      expect(find.text('Grade 9 A'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('Promote: 2'), findsOneWidget);
    });

    testWidgets('says plainly that nothing has been saved', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.textContaining('Nothing has been saved'), findsOneWidget);
    });

    testWidgets('a class with nothing above it is told it graduates', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            preview: fakePreview(
              targetName: null,
              isGraduating: true,
              students: [fakePromotionStudent(defaultOutcome: PromotionOutcome.graduate)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.textContaining('so these students finish school'), findsOneWidget);
      expect(find.text('Finishing school'), findsOneWidget);
    });

    testWidgets('an empty section says so instead of showing an empty table', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            preview: fakePreview(students: const [], canRun: false, cannotRunReason: 'NOTHING_TO_PROMOTE'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.text('There is nobody in this class to promote.'), findsOneWidget);
      expect(find.text('This class has no students.'), findsOneWidget);
    });

    testWidgets('a class already moved says why it cannot be run', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            preview: fakePreview(
              canRun: false,
              students: [fakePromotionStudent(isBlocked: true, blockedReason: 'Aarav already has a place.')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.textContaining('they all have a place'), findsOneWidget);
      expect(find.text('Aarav already has a place.'), findsOneWidget);
    });

    testWidgets('a weak average is shown as the suggestion it is, not as a decision', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            preview: fakePreview(
              students: [
                fakePromotionStudent(
                  averagePercentage: '21.00',
                  attendancePercentage: 62.5,
                  suggestedOutcome: PromotionOutcome.retain,
                  suggestionReason: 'Average 21.00% is below the school\'s 33% pass mark.',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);

      expect(find.text('21.00%'), findsOneWidget);
      expect(find.text('62.5%'), findsOneWidget);
      expect(find.textContaining('below the school'), findsOneWidget);
      // The row still reads Promote: a suggestion never moves the default.
      expect(find.text('Promote: 1'), findsOneWidget);
    });
  });

  group('deciding on screen', () {
    testWidgets('changing one student updates the counts', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.tap(find.byKey(const Key('outcome-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retain').last);
      await tester.pumpAndSettle();

      expect(find.text('Promote: 1'), findsOneWidget);
      expect(find.text('Retain: 1'), findsOneWidget);
    });

    testWidgets('a blocked student is shown and cannot be asked for', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            preview: fakePreview(
              students: [
                fakePromotionStudent(),
                fakePromotionStudent(studentId: 2, name: 'Bina Kapoor', isBlocked: true, blockedReason: 'Already in.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);

      final blocked = tester.widget<DropdownButtonFormField<PromotionOutcome>>(find.byKey(const Key('outcome-2')));
      expect(blocked.onChanged, isNull);
      expect(find.text('Bina Kapoor'), findsOneWidget, reason: 'listed, never quietly dropped');
    });

    testWidgets('graduate all applies to the class', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Graduate all'));
      await tester.pumpAndSettle();

      expect(find.text('Graduate: 2'), findsOneWidget);
      expect(find.text('Promote: 0'), findsOneWidget);
    });

    testWidgets('the search hides rows without forgetting the whole class', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.enterText(find.byKey(const Key('promotion-search')), 'Bina');
      await tester.pumpAndSettle();

      expect(find.text('Aarav Sharma'), findsNothing);
      expect(find.text('Bina Kapoor'), findsOneWidget);
      expect(find.text('Promote: 2'), findsOneWidget, reason: 'the counts describe the class, not the search');
    });

    testWidgets('a search matching nobody says so', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.enterText(find.byKey(const Key('promotion-search')), 'Nobody');
      await tester.pumpAndSettle();

      expect(find.text('No student matches that search.'), findsOneWidget);
    });

    testWidgets('reset puts the rows back', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Graduate all'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset to suggestions'));
      await tester.pumpAndSettle();

      expect(find.text('Promote: 2'), findsOneWidget);
    });

    testWidgets('change class goes back to the first step with the choices kept', (tester) async {
      useDesktop(tester);
      final fake = FakePromotionRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Change class'));
      await tester.pumpAndSettle();

      expect(find.text('Class to promote'), findsOneWidget);
      // Straight back in, without re-picking: the choices survived.
      await tester.tap(find.widgetWithText(FilledButton, 'Review students'));
      await tester.pumpAndSettle();

      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(fake.calls, 2);
    });
  });
}
