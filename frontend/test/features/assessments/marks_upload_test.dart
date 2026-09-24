import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/application/assessment_sheet_notifier.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/presentation/assessment_list_screen.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/imports/data/import_repository.dart';
import 'package:edutrack_app/features/imports/presentation/bulk_import_button.dart';
import 'package:edutrack_app/features/imports/data/models/import_result.dart';
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

Widget wrapList(FakeAssessmentRepository fake, {required UserRole role}) {
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
  group('the notifier', () {
    test('an upload replaces the sheet with what came back', () async {
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry(studentId: 1)]);
      final container = ProviderContainer(
        overrides: [assessmentRepositoryProvider.overrideWithValue(fake)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      final sub = container.listen(assessmentSheetProvider(1), (_, _) {});
      addTearDown(sub.close);
      await container.read(assessmentSheetProvider(1).future);

      await container.read(assessmentSheetProvider(1).notifier).upload(fileName: 'marks.csv', bytes: 'x'.codeUnits);

      expect(fake.lastUploadedFileName, 'marks.csv');
      expect(container.read(assessmentSheetProvider(1)).value!.entries.single.marksObtained, '15');
      expect(container.read(assessmentSheetProvider(1).notifier).isDirty, isFalse);
    });

    test('a refused file rethrows with the rows that need fixing', () async {
      final fake = FakeAssessmentRepository(
        sheetEntries: [fakeEntry(studentId: 1)],
        refuseUploadWith: const BulkImportFailure(
          message: 'Nothing was imported.',
          rows: [
            ImportRowError(row: 3, messages: ['The marks must be between 0 and 20.00.']),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [assessmentRepositoryProvider.overrideWithValue(fake)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      final sub = container.listen(assessmentSheetProvider(1), (_, _) {});
      addTearDown(sub.close);
      await container.read(assessmentSheetProvider(1).future);

      await expectLater(
        container.read(assessmentSheetProvider(1).notifier).upload(fileName: 'marks.csv', bytes: 'x'.codeUnits),
        throwsA(isA<BulkImportFailure>()),
      );
    });
  });

  group('the sheet dialog', () {
    testWidgets('offers the spreadsheet to whoever may mark it', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrapSheet(FakeAssessmentRepository(sheetEntries: [fakeEntry()])));
      await open(tester);

      expect(find.text('Download sheet'), findsOneWidget);
    });

    testWidgets('offers nothing of the sort on a published test', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrapSheet(
          FakeAssessmentRepository(sheetEntries: [fakeEntry()]),
          assessment: fakeAssessment(status: AssessmentStatus.published),
        ),
      );
      await open(tester);

      expect(find.text('Download sheet'), findsNothing);
      expect(find.text('Upload sheet'), findsNothing);
    });

    testWidgets('or to a role that may only look', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrapSheet(FakeAssessmentRepository(sheetEntries: [fakeEntry()]), canManage: false));
      await open(tester);

      expect(find.text('Download sheet'), findsNothing);
    });

    testWidgets('downloading asks the server for the roster', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(sheetEntries: [fakeEntry()]);

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);
      await tester.tap(find.text('Download sheet'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('marksTemplate'));
    });

    testWidgets('a download that fails says so and leaves the sheet alone', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        sheetEntries: [fakeEntry()],
        failWith: {'marksTemplate': const Failure(code: 'SERVER_ERROR', message: 'The sheet is unavailable.')},
      );

      await tester.pumpWidget(wrapSheet(fake));
      await open(tester);
      await tester.tap(find.text('Download sheet'));
      await tester.pumpAndSettle();

      expect(find.text('The sheet is unavailable.'), findsOneWidget);
    });
  });

  group('the class tests screen', () {
    testWidgets('offers Bulk Upload to an administrator', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrapList(FakeAssessmentRepository(), role: UserRole.schoolAdmin));
      await tester.pumpAndSettle();

      // The button hides its own label where no file can be chosen - the
      // test VM, and the Android build - so what is asserted is that the
      // screen offers it at all.
      expect(find.byType(BulkImportButton), findsOneWidget);
    });

    testWidgets('and not to a teacher, who sets their own one at a time', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrapList(FakeAssessmentRepository(), role: UserRole.teacher));
      await tester.pumpAndSettle();

      expect(find.text('New Test'), findsOneWidget);
      expect(find.byType(BulkImportButton), findsNothing);
    });

    testWidgets('nor to an HOD, for the same reason', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrapList(FakeAssessmentRepository(), role: UserRole.hod));
      await tester.pumpAndSettle();

      expect(find.byType(BulkImportButton), findsNothing);
    });
  });
}
