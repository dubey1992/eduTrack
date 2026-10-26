import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_setup.dart';
import 'package:edutrack_app/features/my_teaching/presentation/new_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_assessment_repository.dart';

/// Setting a class test on the phone (docs/teacher-app.md, T5).
void main() {
  final setup = AssessmentSetup(
    classes: const [
      TaughtClass(classSectionId: 622, classSection: 'Grade 3 A', subjectId: 658, subjectName: 'Mathematics'),
      TaughtClass(classSectionId: 623, classSection: 'Grade 4 A', subjectId: 659, subjectName: 'Science'),
    ],
    terms: [
      SetupTerm(id: 1, name: 'Term 1', startDate: DateTime(2026, 4, 1), endDate: DateTime(2026, 9, 30)),
      SetupTerm(id: 2, name: 'Term 2', startDate: DateTime(2026, 10, 1), endDate: DateTime(2027, 3, 31)),
    ],
    gradeScales: const [
      SetupGradeScale(id: 4, name: 'Old scale', isDefault: false),
      SetupGradeScale(id: 5, name: 'CBSE', isDefault: true),
    ],
    passPercentage: 33,
  );

  late FakeAssessmentRepository repository;
  late Object? popped;

  setUp(() {
    repository = FakeAssessmentRepository(setupData: setup);
    popped = null;
  });

  Future<void> pump(WidgetTester tester, {DateTime? today}) async {
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
            body: TextButton(
              onPressed: () async => popped = await context.push<int>('/new'),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/new',
          builder: (context, state) => NewTestScreen(today: today ?? DateTime(2026, 10, 26)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [assessmentRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('new-test-submit')));
    await tester.tap(find.byKey(const Key('new-test-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('offers only the classes the teacher teaches, the term of the day and the default scale', (tester) async {
    await pump(tester);

    expect(find.text('Mathematics · Grade 3 A'), findsOneWidget);
    expect(find.text('10/26/2026'), findsOneWidget);
    expect(find.text('Term 2'), findsOneWidget);
    expect(find.text('Grades by the CBSE scale.'), findsOneWidget);
    expect(find.text('Optional. Blank: 33% of the maximum'), findsOneWidget);
  });

  testWidgets('title and maximum are required, and the maximum has to be a positive number', (tester) async {
    await pump(tester);
    await submit(tester);

    expect(find.text('Give the test a title.'), findsOneWidget);
    expect(find.text('Out of how many marks?'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-test-max')), '0');
    await tester.pump();
    expect(find.text('The maximum has to be more than 0.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-test-max')), 'abc');
    await tester.pump();
    expect(find.text('Enter a number, like 20 or 25.5.'), findsOneWidget);
    expect(repository.calls, isNot(contains('create')));
  });

  testWidgets('a pass mark above the maximum is caught', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('new-test-title')), 'Fractions');
    await tester.enterText(find.byKey(const Key('new-test-max')), '20');
    await tester.enterText(find.byKey(const Key('new-test-pass')), '25');
    await submit(tester);

    expect(find.text('Between 0 and the maximum.'), findsOneWidget);
    expect(repository.calls, isNot(contains('create')));
  });

  testWidgets('sets the test for the chosen class, in the term of its day, and returns its id', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('new-test-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Science · Grade 4 A').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-test-title')), '  Plants - quiz ');
    await tester.enterText(find.byKey(const Key('new-test-max')), '25');
    await submit(tester);

    expect(repository.lastCreated, {
      'class_section_id': 623,
      'subject_id': 659,
      'academic_term_id': 2,
      'grade_scale_id': 5,
      'type': 'class_test',
      'title': 'Plants - quiz',
      'max_marks': '25',
      'pass_marks': null,
      'assessment_date': DateTime(2026, 10, 26),
    });
    expect(popped, isA<int>(), reason: 'the list opens the new test for its marks');
  });

  testWidgets('a day no term covers is refused before anything is sent', (tester) async {
    await pump(tester, today: DateTime(2027, 5, 10));
    expect(find.text('No term covers this day'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-test-title')), 'Fractions');
    await tester.enterText(find.byKey(const Key('new-test-max')), '20');
    await submit(tester);

    expect(find.byKey(const Key('new-test-problem')), findsOneWidget);
    expect(repository.calls, isNot(contains('create')));
  });

  testWidgets("the server's validation is shown, and the form stays", (tester) async {
    repository = FakeAssessmentRepository(
      setupData: setup,
      failWith: {
        'create': const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'weightage': ['The weightage of this term would go over 100%.'],
            },
          },
        ),
      },
    );
    await pump(tester);
    await tester.enterText(find.byKey(const Key('new-test-title')), 'Fractions');
    await tester.enterText(find.byKey(const Key('new-test-max')), '20');
    await submit(tester);

    expect(find.text('The weightage of this term would go over 100%.'), findsOneWidget);
    expect(popped, isNull);
  });

  testWidgets('without signal, says nothing was saved', (tester) async {
    repository = FakeAssessmentRepository(setupData: setup, failWith: {'create': Failure.network()});
    await pump(tester);
    await tester.enterText(find.byKey(const Key('new-test-title')), 'Fractions');
    await tester.enterText(find.byKey(const Key('new-test-max')), '20');
    await submit(tester);

    expect(find.textContaining('No connection. Nothing was saved'), findsOneWidget);
  });

  testWidgets('somebody with no classes on the timetable is told why there is nothing to set', (tester) async {
    repository = FakeAssessmentRepository();
    await pump(tester);

    expect(find.byKey(const Key('new-test-no-classes')), findsOneWidget);
  });

  testWidgets('a school year with no terms says who sets them up', (tester) async {
    repository = FakeAssessmentRepository(
      setupData: AssessmentSetup(classes: setup.classes, terms: const [], gradeScales: const [], passPercentage: 33),
    );
    await pump(tester);

    expect(find.byKey(const Key('new-test-no-terms')), findsOneWidget);
    expect(find.byKey(const Key('new-test-submit')), findsNothing);
  });

  testWidgets('the form that cannot load offers Retry', (tester) async {
    repository = FakeAssessmentRepository(failWith: {'setup': Failure.network()});
    await pump(tester);

    expect(find.text('Retry'), findsOneWidget);
  });
}
