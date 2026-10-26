import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/my_teaching/presentation/marks_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_assessment_repository.dart';

/// Entering a class test's marks on the phone (docs/teacher-app.md, T5).
void main() {
  SheetEntry student(int id, String name, {String? marks, bool absent = false, String? grade, bool? passed}) =>
      SheetEntry(
        studentId: id,
        studentName: name,
        admissionNumber: 'ADM-$id',
        rollNumber: '$id',
        marksObtained: marks,
        isAbsent: absent,
        grade: grade,
        percentage: null,
        passed: passed,
        remarks: null,
      );

  late FakeAssessmentRepository repository;

  setUp(() {
    repository = FakeAssessmentRepository(
      sheetEntries: [student(1, 'Aarav Shah'), student(2, 'Diya Patel'), student(3, 'Kabir Rao')],
    );
  });

  Future<void> pump(WidgetTester tester, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/list',
      routes: [
        GoRoute(
          path: '/list',
          builder: (context, state) => Scaffold(
            body: TextButton(onPressed: () => context.push('/sheet'), child: const Text('open')),
          ),
        ),
        GoRoute(path: '/sheet', builder: (context, state) => const MarksEntryScreen(assessmentId: 1)),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [assessmentRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(theme: theme ?? AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, int id, String marks) async {
    await tester.enterText(find.byKey(Key('marks-box-$id')), marks);
    await tester.pump();
  }

  FilledButton save(WidgetTester tester) => tester.widget(find.byKey(const Key('marks-save')));
  OutlinedButton publish(WidgetTester tester) => tester.widget(find.byKey(const Key('marks-publish')));

  testWidgets('shows the class with how many are marked, out of the maximum', (tester) async {
    await pump(tester);

    expect(find.text('Fractions - unit test'), findsOneWidget);
    expect(find.text('0 of 3 marked'), findsOneWidget);
    expect(find.textContaining('Out of 20'), findsOneWidget);
    expect(save(tester).onPressed, isNull, reason: 'nothing typed, nothing to save');
    expect(publish(tester).onPressed, isNull, reason: 'nobody marked yet');
  });

  testWidgets('the count follows the marks and absences as they are entered', (tester) async {
    await pump(tester);

    await type(tester, 1, '17.5');
    await tester.tap(find.byKey(const Key('marks-absent-2')));
    await tester.pump();

    expect(find.text('2 of 3 marked'), findsOneWidget);
  });

  testWidgets('a mark over the maximum or not a number is caught before saving', (tester) async {
    await pump(tester);

    await type(tester, 1, '25');
    expect(find.text('Out of 20'), findsOneWidget);
    expect(save(tester).onPressed, isNull);
    expect(find.text('1 mark is not a number or is out of range. Fix it to save.'), findsOneWidget);

    await type(tester, 1, '1.2.3');
    expect(find.text('Not a number'), findsOneWidget);
    expect(save(tester).onPressed, isNull);

    await type(tester, 1, '20');
    expect(find.text('Out of 20'), findsNothing);
    expect(find.byKey(const Key('marks-fix-first')), findsNothing);
    expect(save(tester).onPressed, isNotNull, reason: 'exactly the maximum is a mark');
  });

  testWidgets('letters cannot be typed into a mark at all', (tester) async {
    await pump(tester);

    await type(tester, 1, 'ab1c2');

    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
  });

  testWidgets('absent clears the mark and locks the box: absent is not zero', (tester) async {
    await pump(tester);
    await type(tester, 2, '9');

    await tester.tap(find.byKey(const Key('marks-absent-2')));
    await tester.pump();

    final box = tester.widget<TextField>(find.byKey(const Key('marks-box-2')));
    expect(box.enabled, isFalse);
    expect(box.controller!.text, isEmpty);
  });

  testWidgets('a partial sheet saves, sending blanks as not yet marked', (tester) async {
    await pump(tester);
    await type(tester, 1, '17.5');
    await tester.tap(find.byKey(const Key('marks-absent-3')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('marks-save')));
    await tester.pumpAndSettle();

    expect(find.text('Marks saved.'), findsOneWidget);
    final sent = {for (final entry in repository.lastSaved!) entry.studentId: entry};
    expect(sent[1]!.marksObtained, '17.5');
    expect(sent[2]!.isMarked, isFalse, reason: 'a blank is not a zero');
    expect(sent[3]!.isAbsent, isTrue);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets("the server's objection lands on the student it is about", (tester) async {
    repository = FakeAssessmentRepository(
      sheetEntries: [student(1, 'Aarav Shah'), student(2, 'Diya Patel')],
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
    await pump(tester);
    await type(tester, 2, '5');

    await tester.tap(find.byKey(const Key('marks-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Some marks were not accepted'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('marks-row-2')),
        matching: find.text('The marks must be between 0 and 20.00.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without signal the marks stay on the screen to save again', (tester) async {
    repository = FakeAssessmentRepository(
      sheetEntries: [student(1, 'Aarav Shah')],
      failWith: {'saveMarks': Failure.network()},
    );
    await pump(tester);
    await type(tester, 1, '12');

    await tester.tap(find.byKey(const Key('marks-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your marks are still here'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
    expect(save(tester).onPressed, isNotNull);
  });

  testWidgets('Next on the keyboard moves to the next student', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('marks-box-1')));
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final second = tester.widget<TextField>(find.byKey(const Key('marks-box-2')));
    expect(second.focusNode!.hasFocus, isTrue);
  });

  testWidgets('leaving with unsaved marks asks first; staying keeps them', (tester) async {
    await pump(tester);
    await type(tester, 1, '12');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('marks-leave-confirm')), findsOneWidget);

    await tester.tap(find.text('Keep entering'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('marks-leave-discard')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget, reason: 'back on the list');
  });

  testWidgets('publish waits until everyone is marked and saved, then asks, then locks', (tester) async {
    repository = FakeAssessmentRepository(sheetEntries: [student(1, 'Aarav Shah', marks: '15.00')]);
    await pump(tester);
    expect(publish(tester).onPressed, isNotNull);

    await type(tester, 1, '16');
    expect(publish(tester).onPressed, isNull, reason: 'unsaved changes are not published');
    await tester.tap(find.byKey(const Key('marks-save')));
    await tester.pumpAndSettle();

    repository.sheetAssessment = fakeAssessment(status: AssessmentStatus.published);
    await tester.tap(find.byKey(const Key('marks-publish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('marks-publish-confirm')), findsOneWidget);
    expect(find.textContaining('guardians are told'), findsOneWidget);

    await tester.tap(find.byKey(const Key('marks-publish-yes')));
    await tester.pumpAndSettle();

    expect(repository.calls, contains('publish'));
    expect(find.text('Results published.'), findsOneWidget);
    expect(find.byKey(const Key('marks-published')), findsOneWidget);
    expect(find.byKey(const Key('marks-save')), findsNothing);
  });

  testWidgets('a published test is read-only, with grades', (tester) async {
    repository = FakeAssessmentRepository(
      sheetEntries: [
        student(1, 'Aarav Shah', marks: '18.00', grade: 'A1', passed: true),
        student(2, 'Diya Patel', marks: '4.00', grade: 'E', passed: false),
        student(3, 'Kabir Rao', absent: true),
      ],
      sheetAssessment: fakeAssessment(status: AssessmentStatus.published),
    );
    await pump(tester);

    expect(find.byKey(const Key('marks-published')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('18 / 20'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
  });

  testWidgets('a sheet that cannot be loaded offers Retry', (tester) async {
    repository = FakeAssessmentRepository(failWith: {'sheet': Failure.network()});
    await pump(tester);

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('fits a phone in the dark theme', (tester) async {
    await pump(tester, theme: AppTheme.teacherDark());
    await type(tester, 1, '25');

    expect(tester.takeException(), isNull);
  });
}
