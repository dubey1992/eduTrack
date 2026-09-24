import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/application/assessment_sheet_notifier.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assessment_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/session_users.dart';

ProviderContainer containerWith(FakeAssessmentRepository fake) {
  final container = ProviderContainer(
    overrides: [assessmentRepositoryProvider.overrideWithValue(fake)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);

  return container;
}

Future<AssessmentSheet> load(ProviderContainer container, int assessmentId) async {
  final sub = container.listen(assessmentSheetProvider(assessmentId), (_, _) {});
  addTearDown(sub.close);

  return container.read(assessmentSheetProvider(assessmentId).future);
}

Widget wrap(FakeAssessmentRepository fake, {Assessment? assessment, bool canManage = true}) {
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

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the sheet model', () {
    test('a blank is not marked, a mark and an absence both are', () {
      expect(fakeEntry().isMarked, isFalse);
      expect(fakeEntry(marks: '17.50').isMarked, isTrue);
      expect(fakeEntry(isAbsent: true).isMarked, isTrue);
    });

    test('counts what is left to mark', () {
      final sheet = fakeSheet(
        entries: [
          fakeEntry(studentId: 1, marks: '10'),
          fakeEntry(studentId: 2),
          fakeEntry(studentId: 3, isAbsent: true),
        ],
      );

      expect(sheet.markedCount, 2);
      expect(sheet.isComplete, isFalse);
    });

    test('an empty class is not a complete sheet', () {
      expect(fakeSheet(entries: const []).isComplete, isFalse);
    });

    test('a mark reads back for editing without its trailing zeros', () {
      expect(fakeEntry(marks: '17.50').marksForEditing, '17.5');
      expect(fakeEntry(marks: '20.00').marksForEditing, '20');
      expect(fakeEntry().marksForEditing, '');
    });

    test('an absent student sends no mark, whatever was typed before', () {
      final json = fakeEntry(marks: '10', isAbsent: true).toJson();

      expect(json['marks_obtained'], isNull);
      expect(json['is_absent'], isTrue);
    });
  });

  group('the notifier', () {
    test('typing a mark keeps it in memory and sends nothing', () async {
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1)]);
      final container = containerWith(fake);
      await load(container, 1);

      container.read(assessmentSheetProvider(1).notifier).setMark(1, '17.5');

      expect(container.read(assessmentSheetProvider(1)).value!.entries.single.marksObtained, '17.5');
      expect(fake.calls, isNot(contains('saveMarks')));
      expect(container.read(assessmentSheetProvider(1).notifier).isDirty, isTrue);
    });

    test('marking somebody absent clears the mark they had', () async {
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, marks: '10')]);
      final container = containerWith(fake);
      await load(container, 1);

      container.read(assessmentSheetProvider(1).notifier).setAbsent(1, true);

      final entry = container.read(assessmentSheetProvider(1)).value!.entries.single;
      expect(entry.isAbsent, isTrue);
      expect(entry.marksObtained, isNull);
    });

    test('typing a mark takes back an absence', () async {
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, isAbsent: true)]);
      final container = containerWith(fake);
      await load(container, 1);

      container.read(assessmentSheetProvider(1).notifier).setMark(1, '12');

      final entry = container.read(assessmentSheetProvider(1)).value!.entries.single;
      expect(entry.isAbsent, isFalse);
      expect(entry.marksObtained, '12');
    });

    test('clearing the box removes the mark rather than storing a zero', () async {
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, marks: '10')]);
      final container = containerWith(fake);
      await load(container, 1);

      container.read(assessmentSheetProvider(1).notifier).setMark(1, '');

      expect(container.read(assessmentSheetProvider(1)).value!.entries.single.marksObtained, isNull);
    });

    test('one save sends the whole class', () async {
      final fake = FakeAssessmentRepository(
        sheetEntries: [fakeEntry(studentId: 1), fakeEntry(studentId: 2), fakeEntry(studentId: 3)],
      );
      final container = containerWith(fake);
      await load(container, 1);

      container.read(assessmentSheetProvider(1).notifier).setMark(1, '17');
      await container.read(assessmentSheetProvider(1).notifier).save();

      expect(fake.calls.where((call) => call == 'saveMarks').length, 1);
      expect(fake.lastSaved!.length, 3);
      expect(container.read(assessmentSheetProvider(1).notifier).isDirty, isFalse);
    });

    test('a refused save rethrows and keeps what was typed', () async {
      final fake = FakeAssessmentRepository(
        sheetEntries: [fakeEntry(studentId: 1)],
        failWith: {'saveMarks': const Failure(code: 'VALIDATION_ERROR', message: 'The given data was invalid.')},
      );
      final container = containerWith(fake);
      await load(container, 1);
      container.read(assessmentSheetProvider(1).notifier).setMark(1, '99');

      await expectLater(container.read(assessmentSheetProvider(1).notifier).save(), throwsA(isA<Failure>()));

      expect(container.read(assessmentSheetProvider(1)).value!.entries.single.marksObtained, '99');
    });
  });

  group('the dialog', () {
    testWidgets('shows the class with what is left to mark', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        sheetEntries: [
          fakeEntry(studentId: 1, name: 'Aarav Sharma', marks: '17.50'),
          fakeEntry(studentId: 2, name: 'Bina Kapoor'),
        ],
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      expect(find.text('Marks · Fractions - unit test'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('1 of 2 marked'), findsOneWidget);
      expect(find.textContaining('out of 20'), findsOneWidget);
    });

    testWidgets('says when the class is empty', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeAssessmentRepository(sheetEntries: const [])));
      await open(tester);

      expect(find.textContaining('nobody to mark'), findsOneWidget);
    });

    testWidgets('offers a retry when the sheet cannot be loaded', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        failWith: {'sheet': const Failure(code: 'SERVER_ERROR', message: 'The sheet is unavailable.')},
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      expect(find.text('The sheet is unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('typing a mark and saving sends it once', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, name: 'Aarav Sharma')]);

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Marks'), '17.5');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
      await tester.pump();
      await tester.pump();

      expect(fake.lastSaved!.single.marksObtained, '17.5');
      expect(find.text('Marks saved.'), findsOneWidget);
    });

    testWidgets('marking absent empties and disables the box', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, marks: '10')]);

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Absent'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Marks')).enabled, isFalse);
      expect(find.text('Absent'), findsWidgets);
    });

    testWidgets("a refusal lands on the row the server named", (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        sheetEntries: [
          fakeEntry(studentId: 1, name: 'Aarav Sharma'),
          fakeEntry(studentId: 2, name: 'Bina Kapoor'),
        ],
        failWith: {
          'saveMarks': const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'marks.1.marks_obtained': ['The marks must be between 0 and 20.00.'],
              },
            },
          ),
        },
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
      await tester.pumpAndSettle();

      expect(find.text('The marks must be between 0 and 20.00.'), findsOneWidget);
      expect(find.textContaining('See the rows below'), findsOneWidget);
    });

    testWidgets('a published test is read-only, with no Save', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1, marks: '17.50')]);

      await tester.pumpWidget(wrap(fake, assessment: fakeAssessment(status: AssessmentStatus.published)));
      await open(tester);

      expect(find.text('Save Marks'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Marks')).enabled, isFalse);
    });

    testWidgets('a role that may only look gets no Save either', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1)]);

      await tester.pumpWidget(wrap(fake, canManage: false));
      await open(tester);

      expect(find.text('Save Marks'), findsNothing);
      expect(find.byType(FilterChip), findsOneWidget);
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).onSelected, isNull);
    });
  });
}
