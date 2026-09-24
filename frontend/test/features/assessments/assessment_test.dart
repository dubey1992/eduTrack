import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paged_list.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/application/assessment_list_notifier.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/presentation/assessment_list_screen.dart';
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

Future<PagedList<Assessment>> load(ProviderContainer container) async {
  final sub = container.listen(assessmentListNotifierProvider, (_, _) {});
  addTearDown(sub.close);

  return container.read(assessmentListNotifierProvider.future);
}

Widget wrap(FakeAssessmentRepository fake, {UserRole role = UserRole.schoolAdmin}) {
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
  tester.view.physicalSize = const Size(2200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the model', () {
    test('reads marks without the noise of trailing zeros', () {
      expect(fakeAssessment(maxMarks: '20.00').maxMarksLabel, '20');
      expect(fakeAssessment(maxMarks: '17.50').maxMarksLabel, '17.5');
    });

    test('names each kind of test in words a school would use', () {
      expect(AssessmentType.unitTest.label, 'Unit test');
      expect(AssessmentType.practical.label, 'Practical');
    });

    test('a kind or status it has not seen before does not crash a screen', () {
      final row = Assessment.fromJson({
        'id': 1,
        'school_id': 1,
        'academic_term_id': 2,
        'term_name': 'Term 1',
        'class_section_id': 3,
        'class_section_name': 'Grade 8 A',
        'subject_id': 5,
        'subject_name': 'Mathematics',
        'syllabus_topic_id': null,
        'syllabus_topic_title': null,
        'grade_scale_id': null,
        'grade_scale_name': null,
        'type': 'viva',
        'title': 'Something new',
        'max_marks': '20.00',
        'pass_marks': null,
        'weightage': null,
        'assessment_date': '2026-04-15',
        'status': 'archived',
        'created_by_name': 'Asha Admin',
      });

      expect(row.type, AssessmentType.classTest);
      expect(row.status, AssessmentStatus.draft);
    });

    test('a draft is a draft, and a published test is not', () {
      expect(fakeAssessment().isDraft, isTrue);
      expect(fakeAssessment(status: AssessmentStatus.published).isDraft, isFalse);
    });
  });

  group('the list', () {
    test('loads what the API sends', () async {
      final fake = FakeAssessmentRepository(
        assessments: [
          fakeAssessment(),
          fakeAssessment(id: 2, title: 'Algebra'),
        ],
      );

      final page = await load(containerWith(fake));

      expect(page.items.map((row) => row.title), ['Fractions - unit test', 'Algebra']);
    });

    test('a filter narrows the list and goes back to the first page', () async {
      final fake = FakeAssessmentRepository(
        assessments: [
          fakeAssessment(),
          fakeAssessment(id: 2, title: 'Other class', classSectionId: 9),
        ],
      );
      final container = containerWith(fake);
      await load(container);

      await container.read(assessmentListNotifierProvider.notifier).goToPage(2);
      await container.read(assessmentListNotifierProvider.notifier).setSectionFilter(9);

      final page = container.read(assessmentListNotifierProvider).value!;
      expect(page.items.map((row) => row.title), ['Other class']);
      expect(page.currentPage, 1);
      expect(fake.lastSectionFilter, 9);
    });

    test('the status filter reaches the repository', () async {
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment()]);
      final container = containerWith(fake);
      await load(container);

      await container.read(assessmentListNotifierProvider.notifier).setStatusFilter('published');

      expect(fake.lastStatusFilter, 'published');
      expect(container.read(assessmentListNotifierProvider).value!.items, isEmpty);
    });

    test('creating one refreshes the list', () async {
      final fake = FakeAssessmentRepository();
      final container = containerWith(fake);
      await load(container);

      await container
          .read(assessmentListNotifierProvider.notifier)
          .createAssessment(
            classSectionId: 3,
            subjectId: 5,
            academicTermId: 2,
            type: 'class_test',
            title: 'New test',
            maxMarks: '20',
            assessmentDate: DateTime(2026, 4, 15),
          );

      expect(container.read(assessmentListNotifierProvider).value!.items.single.title, 'New test');
      expect(fake.calls, ['listPage', 'create', 'listPage']);
    });

    test('a failed create leaves the list alone and rethrows for the dialog', () async {
      final fake = FakeAssessmentRepository(
        failWith: {'create': const Failure(code: 'VALIDATION_ERROR', message: 'Mathematics is not taught at Grade 8.')},
      );
      final container = containerWith(fake);
      await load(container);

      await expectLater(
        container
            .read(assessmentListNotifierProvider.notifier)
            .createAssessment(
              classSectionId: 3,
              subjectId: 5,
              academicTermId: 2,
              type: 'class_test',
              title: 'New test',
              maxMarks: '20',
              assessmentDate: DateTime(2026, 4, 15),
            ),
        throwsA(isA<Failure>()),
      );
      expect(container.read(assessmentListNotifierProvider).value!.items, isEmpty);
    });

    test('deleting one drops it', () async {
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(id: 4)]);
      final container = containerWith(fake);
      final page = await load(container);

      await container.read(assessmentListNotifierProvider.notifier).deleteAssessment(page.items.single);

      expect(container.read(assessmentListNotifierProvider).value!.items, isEmpty);
    });
  });

  group('the screen', () {
    testWidgets('shows each test with its class, subject and total', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeAssessmentRepository(assessments: [fakeAssessment()])));
      await tester.pumpAndSettle();

      expect(find.text('Fractions - unit test'), findsOneWidget);
      expect(find.text('Grade 8 A'), findsWidgets);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.descendant(of: find.byType(DataTable), matching: find.text('20')), findsOneWidget);
      expect(find.text('Draft'), findsWidgets);
    });

    testWidgets('says when there are none', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeAssessmentRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No class tests yet.'), findsOneWidget);
    });

    testWidgets('offers a retry when the list cannot be loaded', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        failWith: {'listPage': const Failure(code: 'SERVER_ERROR', message: 'Tests are unavailable.')},
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Tests are unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a switched-off module reads as switched off, with no retry', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        failWith: {
          'listPage': const Failure(
            code: 'MODULE_DISABLED',
            message: 'Class Tests & Assessments is switched off for this school.',
          ),
        },
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Class Tests & Assessments is switched off for this school.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a published test offers no edit or delete', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment(status: AssessmentStatus.published)]);

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit test'), findsNothing);
      expect(find.byTooltip('Delete test'), findsNothing);
      expect(find.text('Published'), findsWidgets);
    });

    testWidgets('a draft offers both', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeAssessmentRepository(assessments: [fakeAssessment()])));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit test'), findsOneWidget);
      expect(find.byTooltip('Delete test'), findsOneWidget);
    });

    testWidgets('deleting asks first, and does nothing if the answer is no', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment()]);

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete test'));
      await tester.pumpAndSettle();
      expect(find.text('Delete test?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.calls, isNot(contains('delete')));
    });

    testWidgets('a refused delete shows the reason and keeps the test', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(
        assessments: [fakeAssessment()],
        failWith: {
          'delete': const Failure(
            code: 'ASSESSMENT_PUBLISHED',
            message: 'This test has been published. Reopen it before changing anything.',
          ),
        },
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete test'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This test has been published. Reopen it before changing anything.'), findsOneWidget);
      expect(find.text('Fractions - unit test'), findsOneWidget);
    });

    testWidgets('a role with view but not manage gets no New Test button', (tester) async {
      useDesktop(tester);
      final fake = FakeAssessmentRepository(assessments: [fakeAssessment()]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assessmentRepositoryProvider.overrideWithValue(fake),
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                sessionOnRestore: sessionUser(UserRole.teacher, permissions: {...allModulesAt(PermissionLevel.view)}),
              ),
            ),
          ],
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssessmentListScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fractions - unit test'), findsOneWidget);
      expect(find.text('New Test'), findsNothing);
      expect(find.byTooltip('Edit test'), findsNothing);
    });
  });
}
