import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/presentation/assessment_list_screen.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assessment_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/session_users.dart';

Widget wrapSheet(FakeAssessmentRepository fake, {Assessment? assessment, bool canManage = true}) {
  final test = assessment ?? fakeAssessment();

  return ProviderScope(
    overrides: [
      assessmentRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher))),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => MarksSheetDialog(assessment: test, canManage: canManage),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Widget wrapList(FakeAssessmentRepository fake, {UserRole role = UserRole.schoolAdmin}) {
  return ProviderScope(
    overrides: [
      assessmentRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AssessmentListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(2200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('publishing from the sheet', () {
    testWidgets('waits until everybody has a mark or an absence', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        sheetEntries: [
          fakeEntry(studentId: 1, marks: '17.50'),
          fakeEntry(studentId: 2),
        ],
      );

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);

      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Publish')).onPressed, isNull);
    });

    testWidgets('offers itself once the class is marked', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        sheetEntries: [
          fakeEntry(studentId: 1, marks: '17.50'),
          fakeEntry(studentId: 2, isAbsent: true),
        ],
      );

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);

      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Publish')).onPressed, isNotNull);
    });

    testWidgets('asks first, and says what publishing does', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, marks: '17.50')]);

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Publish this result?'), findsOneWidget);
      expect(find.textContaining('fixed as they are now'), findsOneWidget);

      // Two Cancels on screen: the confirmation's and the sheet's behind it.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(fake.calls, isNot(contains('publish')));
    });

    testWidgets('publishes on yes, and says so', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        assessments: [fakeAssessment()],
        sheetEntries: [fakeEntry(studentId: 1, marks: '17.50')],
      );

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Publish'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pump();
      await tester.pump();

      expect(fake.calls, contains('publish'));
      expect(find.text('Result published.'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown and the sheet stays open', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        assessments: [fakeAssessment()],
        sheetEntries: [fakeEntry(studentId: 1, marks: '17.50')],
        failWith: {
          'publish': const Failure(
            code: 'MARKS_INCOMPLETE',
            message: '1 of the class has no mark yet. Mark everybody, or mark them absent, before publishing.',
          ),
        },
      );

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Publish'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no mark yet'), findsOneWidget);
      expect(find.byType(MarksSheetDialog), findsOneWidget);
    });

    testWidgets('a published sheet offers no publishing and reads as a result', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        sheetEntries: [fakeEntry(studentId: 1, marks: '17.50', grade: 'A2', percentage: '87.50', passed: true)],
      );

      await tester.pumpWidget(wrapSheet(fake, assessment: fakeAssessment(status: AssessmentStatus.published)));
      await open(tester);

      expect(find.text('Publish'), findsNothing);
      expect(find.text('A2'), findsOneWidget);
      expect(find.text('87.5%'), findsOneWidget);
    });

    testWidgets('an absent student on a published sheet reads as absent', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, isAbsent: true)]);

      await tester.pumpWidget(wrapSheet(fake, assessment: fakeAssessment(status: AssessmentStatus.published)));
      await open(tester);

      expect(find.text('Absent'), findsWidgets);
    });
  });

  group('reopening from the list', () {
    testWidgets('a published test offers Reopen to a manager', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(status: AssessmentStatus.published)]);

      await tester.pumpWidget(wrapList(fake));
      await tester.pumpAndSettle();

      expect(find.text('Reopen'), findsOneWidget);
      expect(find.byTooltip('Edit test'), findsNothing);
    });

    testWidgets('a draft does not', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrapList(FakeAssessmentRepository(assessments: [fakeAssessment()])));
      await tester.pumpAndSettle();

      expect(find.text('Reopen'), findsNothing);
    });

    testWidgets('asks first, warning that guardians are not told again', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(status: AssessmentStatus.published)]);

      await tester.pumpWidget(wrapList(fake));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reopen'));
      await tester.pumpAndSettle();

      expect(find.text('Reopen this result?'), findsOneWidget);
      expect(find.textContaining('not told again'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(fake.calls, isNot(contains('reopen')));
    });

    testWidgets('reopens on yes and says so', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(status: AssessmentStatus.published)]);

      await tester.pumpWidget(wrapList(fake));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reopen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reopen'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('reopen'));
      expect(find.textContaining('is a draft again'), findsOneWidget);
    });

    testWidgets('a refused reopen shows the reason', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        assessments: [fakeAssessment(status: AssessmentStatus.published)],
        failWith: {'reopen': const Failure(code: 'ASSESSMENT_NOT_PUBLISHED', message: 'This test is already a draft.')},
      );

      await tester.pumpWidget(wrapList(fake));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reopen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reopen'));
      await tester.pumpAndSettle();

      expect(find.text('This test is already a draft.'), findsOneWidget);
    });

    testWidgets('a teacher is offered the marks and no reopening', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(status: AssessmentStatus.published)]);

      await tester.pumpWidget(wrapList(fake, role: UserRole.teacher));
      await tester.pumpAndSettle();

      // The API refuses a teacher's reopen, so the button is not offered
      // either: a button that always fails is worse than no button.
      expect(find.text('Marks'), findsOneWidget);
      expect(find.text('Reopen'), findsNothing);
    });

    testWidgets('an HOD is, because they only ever see their own department', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(status: AssessmentStatus.published)]);

      await tester.pumpWidget(wrapList(fake, role: UserRole.hod));
      await tester.pumpAndSettle();

      expect(find.text('Reopen'), findsOneWidget);
    });
  });
}
