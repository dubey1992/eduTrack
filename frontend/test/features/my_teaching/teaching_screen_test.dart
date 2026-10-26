import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_teaching/presentation/report_detail_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/syllabus_class_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/teaching_screen.dart';
import 'package:edutrack_app/features/syllabus/application/syllabus_checklist_notifier.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_assessment_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_syllabus_progress_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/session_users.dart';
import 'teaching_fixtures.dart';

/// A report fake that pages: two reports a page.
class _PagingReports extends FakeTeachingReportRepository {
  _PagingReports(List<TeachingReport> all) : super(reports: all);

  @override
  Future<PaginatedResponse<TeachingReport>> list({
    int? schoolId,
    int? teacherId,
    String? reportDate,
    bool mine = false,
    bool toReview = false,
    required int page,
    required int perPage,
  }) async {
    lastListMine = mine;
    final slice = reports.skip((page - 1) * 2).take(2).toList();
    return PaginatedResponse(
      items: slice,
      currentPage: page,
      lastPage: (reports.length / 2).ceil(),
      total: reports.length,
      perPage: 2,
    );
  }
}

/// The Teaching tab, a report, and one class's syllabus on the phone
/// (docs/teacher-app.md, T3).
void main() {
  late FakeTeachingReportRepository reports;
  late FakeSyllabusProgressRepository syllabus;
  late FakeAssessmentRepository assessments;

  setUp(() {
    reports = FakeTeachingReportRepository(
      reports: [
        report(id: 1, reviewed: true),
        report(id: 2, date: '2026-10-23', topic: 'Place value'),
      ],
    );
    assessments = FakeAssessmentRepository(
      assessments: [
        fakeAssessment(id: 41, title: 'Fractions - unit test'),
        fakeAssessment(id: 42, title: 'Place value quiz', status: AssessmentStatus.published),
      ],
    );
    syllabus = FakeSyllabusProgressRepository(
      checklist: mathsChecklist(),
      myClasses: const [mathsGrade3A, scienceGrade4A],
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    String at = '/teaching',
    ThemeData? theme,
    Map<String, PermissionLevel>? permissions,
  }) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/teaching/tests/new', builder: (context, state) => const Text('new test form')),
        GoRoute(
          path: '/teaching/tests/:id',
          builder: (context, state) => Text('marks of ${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/teaching',
          builder: (context, state) => const Scaffold(body: TeachingScreen()),
        ),
        GoRoute(
          path: '/teaching/reports/:id',
          builder: (context, state) => ReportDetailScreen(reportId: int.parse(state.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/teaching/syllabus/:sectionId/:subjectId',
          builder: (context, state) => SyllabusClassScreen(
            params: SyllabusChecklistParams(
              classSectionId: int.parse(state.pathParameters['sectionId']!),
              subjectId: int.parse(state.pathParameters['subjectId']!),
            ),
            label: state.uri.queryParameters['label'] ?? 'Syllabus',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teachingReportRepositoryProvider.overrideWithValue(reports),
          syllabusProgressRepositoryProvider.overrideWithValue(syllabus),
          assessmentRepositoryProvider.overrideWithValue(assessments),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: 7, permissions: permissions)),
          ),
        ],
        child: MaterialApp.router(theme: theme ?? AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSyllabusTab(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('teaching-tab-syllabus')));
    await tester.pumpAndSettle();
  }

  group('Reports', () {
    testWidgets('lists only the teacher\'s own reports, newest first, with the review state', (tester) async {
      await pump(tester);

      expect(reports.lastListMine, isTrue, reason: 'always mine=1, whatever the role may see');
      expect(find.byKey(const Key('my-report-1')), findsOneWidget);
      expect(find.byKey(const Key('my-report-2')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('my-report-1')), matching: find.text('Reviewed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('my-report-2')), matching: find.text('Awaiting review')),
        findsOneWidget,
      );
      expect(find.text('10/26/2026 · Grade 3 A · Period 1'), findsOneWidget);
    });

    testWidgets('with none yet, says where reports come from', (tester) async {
      reports = FakeTeachingReportRepository();
      await pump(tester);

      expect(find.byKey(const Key('my-reports-empty')), findsOneWidget);
      expect(find.textContaining('tap it on Today'), findsOneWidget);
    });

    testWidgets('an error offers Retry, which tries again', (tester) async {
      reports.failListWith = Failure.network();
      await pump(tester);

      expect(find.text('Retry'), findsOneWidget);
      reports.failListWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-report-1')), findsOneWidget);
    });

    testWidgets('older reports load a page at a time', (tester) async {
      reports = _PagingReports([for (var id = 1; id <= 3; id++) report(id: id)]);
      await pump(tester);

      expect(find.byKey(const Key('my-report-3')), findsNothing);
      await tester.tap(find.byKey(const Key('my-reports-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-report-3')), findsOneWidget);
      expect(find.byKey(const Key('my-reports-more')), findsNothing);
    });

    testWidgets('a report opens whole, with who reviewed it', (tester) async {
      reports = FakeTeachingReportRepository(
        reports: [report(reviewed: true, homework: 'Exercise 4.2', syllabusTopicName: 'Fractions')],
      );
      await pump(tester);

      await tester.tap(find.byKey(const Key('my-report-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-detail')), findsOneWidget);
      expect(find.text('Fractions: adding unlike denominators'), findsOneWidget);
      expect(find.text('Exercise 4.2'), findsOneWidget);
      expect(find.text('Fractions'), findsOneWidget);
      expect(find.text('Reviewed by Rohit Verma on 10/26/2026.'), findsOneWidget);
      expect(find.text('Remarks'), findsNothing, reason: 'an empty field is left out, not shown blank');
    });

    testWidgets('a report that cannot be loaded offers Retry', (tester) async {
      reports.failGetWith = const Failure(code: 'NOT_FOUND', message: 'Not found.');
      await pump(tester, at: '/teaching/reports/1');

      expect(find.text('Not found.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Syllabus', () {
    testWidgets('lists each class and subject taught, with how far it has got', (tester) async {
      await pump(tester);
      await openSyllabusTab(tester);

      expect(find.byKey(const Key('my-syllabus-622-31')), findsOneWidget);
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.text('No topics yet'), findsOneWidget, reason: 'Science has no outline');
    });

    testWidgets('with no classes on the timetable, says who sets that up', (tester) async {
      syllabus.myClasses = const [];
      await pump(tester);
      await openSyllabusTab(tester);

      expect(find.byKey(const Key('my-syllabus-empty')), findsOneWidget);
    });

    testWidgets('an error offers Retry', (tester) async {
      syllabus.failMineWith = Failure.network();
      await pump(tester);
      await openSyllabusTab(tester);

      expect(find.text('Retry'), findsOneWidget);
      syllabus.failMineWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-syllabus-622-31')), findsOneWidget);
    });

    testWidgets('a class opens its checklist, and ticking a topic saves it', (tester) async {
      await pump(tester);
      await openSyllabusTab(tester);
      await tester.tap(find.byKey(const Key('my-syllabus-622-31')));
      await tester.pumpAndSettle();

      expect(find.text('Mathematics · Grade 3 A'), findsOneWidget);
      expect(find.text('1 of 2 topics done · 50%'), findsOneWidget);
      expect(find.text('Done · Meera Joshi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('syllabus-topic-102')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 topics done · 100%'), findsOneWidget);
    });

    testWidgets('a tick that fails says so and changes nothing', (tester) async {
      syllabus.failToggleWith = Failure.network();
      await pump(tester, at: '/teaching/syllabus/622/31?label=Mathematics');

      await tester.tap(find.byKey(const Key('syllabus-topic-102')));
      await tester.pumpAndSettle();

      expect(find.text('No connection. "Decimals" was not changed.'), findsOneWidget);
      expect(find.text('1 of 2 topics done · 50%'), findsOneWidget);
    });

    testWidgets('a tick the server refuses shows its reason', (tester) async {
      syllabus.failToggleWith = const Failure(code: 'FORBIDDEN', message: 'This action is unauthorized.');
      await pump(tester, at: '/teaching/syllabus/622/31?label=Mathematics');

      await tester.tap(find.byKey(const Key('syllabus-topic-102')));
      await tester.pumpAndSettle();

      expect(find.text('This action is unauthorized.'), findsOneWidget);
    });

    testWidgets('a subject with no topics says who sets them out', (tester) async {
      syllabus = FakeSyllabusProgressRepository(
        checklist: mathsChecklist().copyWithNoTopics(),
        myClasses: const [mathsGrade3A],
      );
      await pump(tester, at: '/teaching/syllabus/622/31?label=Mathematics');

      expect(find.byKey(const Key('syllabus-class-empty')), findsOneWidget);
    });

    testWidgets('fits a phone in the dark theme', (tester) async {
      await pump(tester, at: '/teaching/syllabus/622/31?label=Mathematics · Grade 3 A', theme: AppTheme.teacherDark());

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('syllabus-class-list')), findsOneWidget);
    });
  });

  group('Marks', () {
    Future<void> openMarksTab(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('teaching-tab-marks')));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the tests of the classes taught, mine=1, with their state', (tester) async {
      await pump(tester);
      await openMarksTab(tester);

      expect(assessments.lastMine, isTrue);
      expect(find.descendant(of: find.byKey(const Key('my-test-41')), matching: find.text('Draft')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('my-test-42')), matching: find.text('Published')),
        findsOneWidget,
      );
    });

    testWidgets('a test opens its marks', (tester) async {
      await pump(tester);
      await openMarksTab(tester);

      await tester.tap(find.byKey(const Key('my-test-41')));
      await tester.pumpAndSettle();

      expect(find.text('marks of 41'), findsOneWidget);
    });

    testWidgets('New test opens the form', (tester) async {
      await pump(tester);
      await openMarksTab(tester);

      await tester.tap(find.byKey(const Key('my-tests-new')));
      await tester.pumpAndSettle();

      expect(find.text('new test form'), findsOneWidget);
    });

    testWidgets('with none yet, says how to set one', (tester) async {
      assessments = FakeAssessmentRepository();
      await pump(tester);
      await openMarksTab(tester);

      expect(find.byKey(const Key('my-tests-empty')), findsOneWidget);
    });

    testWidgets('an error offers Retry', (tester) async {
      assessments = FakeAssessmentRepository(failWith: {'listPage': Failure.network()});
      await pump(tester);
      await openMarksTab(tester);

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('a part the school switched off is left out, not shown switched off', (tester) async {
    await pump(tester, permissions: {...allModulesAt(PermissionLevel.manage), 'syllabus': PermissionLevel.none});

    expect(find.byKey(const Key('teaching-tab-reports')), findsOneWidget);
    expect(find.byKey(const Key('teaching-tab-syllabus')), findsNothing);
    expect(find.byKey(const Key('teaching-tab-marks')), findsOneWidget);
  });
}
