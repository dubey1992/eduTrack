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
import 'package:edutrack_app/features/promotion/presentation/promotion_batch_dialog.dart';
import 'package:edutrack_app/features/promotion/presentation/promotion_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_promotion_repository.dart';
import '../../support/session_users.dart';

/// Running the promotion (docs/promotion.md): the last step, the only one
/// that writes, and the one that must never happen twice by accident.
final _sections = [const ClassSectionOption(id: 10, label: 'Grade 8 A')];

AcademicYear _year(int id, String name) => AcademicYear(
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
      academicYearPickerProvider.overrideWith((ref, arg) async => [_year(1, '2026-27'), _year(2, '2027-28')]),
      promotionTargetSectionsProvider.overrideWith((ref, arg) async => const <ClassSectionOption>[]),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: PromotionScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(2200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Promote this class'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Promote'));
  await tester.pumpAndSettle();
}

void main() {
  group('the notifier', () {
    ProviderContainer containerWith(FakePromotionRepository fake) {
      final container = ProviderContainer(overrides: [promotionRepositoryProvider.overrideWithValue(fake)]);
      addTearDown(container.dispose);

      return container;
    }

    Future<ProviderContainer> loaded(FakePromotionRepository fake) async {
      final container = containerWith(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);
      notifier.setSourceSection(10);
      notifier.setTargetYear(2);
      await notifier.loadPreview();

      return container;
    }

    test('sends what is on screen, student by student', () async {
      final fake = FakePromotionRepository();
      final container = await loaded(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setOutcome(2, PromotionOutcome.retain);
      await notifier.run();

      expect(fake.lastRun, {1: 'promote', 2: 'retain'});
      expect(container.read(promotionNotifierProvider).hasRun, isTrue);
    });

    test('never names a blocked student, whose row the server would refuse', () async {
      final fake = FakePromotionRepository(
        preview: fakePreview(
          students: [
            fakePromotionStudent(),
            fakePromotionStudent(studentId: 2, name: 'Bina Kapoor', isBlocked: true, blockedReason: 'Already in.'),
          ],
        ),
      );
      final container = await loaded(fake);

      await container.read(promotionNotifierProvider.notifier).run();

      expect(fake.lastRun, {1: 'promote'});
    });

    test('will not run twice', () async {
      final fake = FakePromotionRepository();
      final container = await loaded(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);

      await notifier.run();
      await notifier.run();

      expect(fake.runs, 1, reason: 'a promotion is the last thing that should happen twice');
    });

    test('runs nothing before a roster has been read', () async {
      final fake = FakePromotionRepository();
      final container = containerWith(fake);

      await container.read(promotionNotifierProvider.notifier).run();

      expect(fake.runs, 0);
    });

    test('a refusal is kept beside the list rather than thrown away', () async {
      final fake = FakePromotionRepository(
        runFailure: const Failure(code: 'ROSTER_CHANGED', message: 'This class has changed since the list.'),
      );
      final container = await loaded(fake);

      final ran = await container.read(promotionNotifierProvider.notifier).run();
      final state = container.read(promotionNotifierProvider);

      expect(ran, isFalse);
      expect(state.error, 'This class has changed since the list.');
      expect(state.hasRun, isFalse, reason: 'nothing was promoted');
      expect(state.isRunning, isFalse);
    });

    test('starting again forgets everything, including the class', () async {
      final container = await loaded(FakePromotionRepository());
      final notifier = container.read(promotionNotifierProvider.notifier);

      await notifier.run();
      notifier.startAgain();
      final state = container.read(promotionNotifierProvider);

      expect(state.hasRun, isFalse);
      expect(state.classSectionId, isNull);
      expect(state.hasPreview, isFalse);
    });
  });

  group('on screen', () {
    testWidgets('asks first, spelling out what happens to how many', (tester) async {
      useDesktop(tester);
      final fake = FakePromotionRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await review(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Promote this class'));
      await tester.pumpAndSettle();

      expect(find.text('Promote this class?'), findsOneWidget);
      expect(find.textContaining('2 promoted to Grade 9 A'), findsOneWidget);
      expect(find.textContaining('cannot be undone from here'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.runs, 0, reason: 'cancel means cancel');
    });

    testWidgets('shows what the run did, not the roster it was working on', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);
      await confirm(tester);

      expect(find.textContaining('has moved into 2027-28'), findsOneWidget);
      expect(find.text('Promoted: 2'), findsOneWidget);
      expect(find.text('Retained: 1'), findsOneWidget);
      expect(find.text('The class has been promoted.'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsNothing, reason: 'that class has just changed');
    });

    testWidgets('a refused run keeps the list and says why', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            runFailure: const Failure(code: 'ROSTER_CHANGED', message: 'This class has changed since the list.'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);
      await confirm(tester);

      expect(find.text('This class has changed since the list.'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget, reason: 'nothing happened, so the list stands');
    });

    testWidgets('a class where nobody can move is not offered the button', (tester) async {
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

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Promote this class')).onPressed, isNull);
    });

    testWidgets('the result opens the list of what happened to each student', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);
      await confirm(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'See what happened to each student'));
      await tester.pumpAndSettle();

      expect(find.byType(PromotionBatchDialog), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Promoted'), findsOneWidget);
      expect(find.text('Grade 9 A'), findsWidgets);
      expect(find.text('Graduated'), findsOneWidget);
    });

    testWidgets('promote another class goes back to an empty first step', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();
      await review(tester);
      await confirm(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Promote another class'));
      await tester.pumpAndSettle();

      expect(find.text('Class to promote'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Review students')).onPressed, isNull);
    });
  });

  group('the history', () {
    testWidgets('says so plainly when nothing has been promoted yet', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Promotions already run'), findsOneWidget);
      expect(find.text('No class has been promoted yet.'), findsOneWidget);
    });

    testWidgets('lists past runs with their counts', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository(history: [fakeBatch()])));
      await tester.pumpAndSettle();

      expect(find.text('Grade 8 A · 2026-27'), findsOneWidget);
      expect(find.text('Grade 9 A · 2027-28'), findsOneWidget);
      expect(find.text('2 up · 1 held · 0 out · 0 left'), findsOneWidget);
      expect(find.text('Asha Admin'), findsOneWidget);
    });

    testWidgets('a batch where everybody graduated says they finished school', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakePromotionRepository(
            history: [fakeBatch(toClassSectionName: null, promoted: 0, retained: 0, graduated: 3)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Finished school · 2027-28'), findsOneWidget);
    });

    testWidgets('View opens one run student by student', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository(history: [fakeBatch()])));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();

      expect(find.byType(PromotionBatchDialog), findsOneWidget);
      expect(find.textContaining('Run by Asha Admin'), findsOneWidget);
      expect(find.text('Bina Kapoor'), findsOneWidget);
    });

    testWidgets('a server that will not answer is shown with a retry', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakePromotionRepository(failure: Failure.network())));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server. Check your connection and try again.'), findsWidgets);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsWidgets);
    });
  });
}
