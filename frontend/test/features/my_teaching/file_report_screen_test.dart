import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_teaching/presentation/file_report_screen.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_syllabus_topic_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_today_repository.dart';
import 'teaching_fixtures.dart';

/// Filing a teaching report on the phone (docs/teacher-app.md, T3).
void main() {
  late FakeTeachingReportRepository reports;
  late FakeSyllabusTopicRepository topics;
  late bool popped;

  setUp(() {
    reports = FakeTeachingReportRepository();
    topics = FakeSyllabusTopicRepository(topics: mathsTopics);
    popped = false;
  });

  const period = ReportPeriod(
    timetableEntryId: 11,
    date: '2026-10-26',
    classSection: 'Grade 3 A',
    subject: 'Mathematics',
    periodNumber: 1,
    subjectId: 31,
  );

  Future<void> pump(WidgetTester tester, {ReportPeriod given = period, ThemeData? theme}) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await context.push<bool>('/form');
                popped = result ?? false;
              },
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) => FileReportScreen(period: given),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teachingReportRepositoryProvider.overrideWithValue(reports),
          syllabusTopicRepositoryProvider.overrideWithValue(topics),
          todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        ],
        child: MaterialApp.router(theme: theme ?? AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('report-submit')));
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows which period it is for, with nothing to choose', (tester) async {
    await pump(tester);

    expect(find.text('Mathematics · Grade 3 A · Period 1'), findsOneWidget);
    expect(find.text('10/26/2026'), findsOneWidget);
  });

  testWidgets('what was taught is required', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), '   ');
    await submit(tester);

    expect(find.text('Say what was taught in this period.'), findsOneWidget);
    expect(reports.lastStorePayload, isNull);
  });

  testWidgets('the message clears as soon as something is typed', (tester) async {
    await pump(tester);
    await submit(tester);
    expect(find.text('Say what was taught in this period.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await tester.pump();

    expect(find.text('Say what was taught in this period.'), findsNothing);
  });

  testWidgets('files the report, trimmed, with blanks sent as nothing', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), '  Fractions: halves and quarters  ');
    await tester.enterText(find.byKey(const Key('report-homework')), ' Exercise 4.2 ');
    await submit(tester);

    expect(reports.lastStorePayload, {
      'timetable_entry_id': 11,
      'report_date': '2026-10-26',
      'topic_taught': 'Fractions: halves and quarters',
      'syllabus_topic_id': null,
      'homework': 'Exercise 4.2',
      'remarks': null,
    });
    expect(find.text('Report filed.'), findsOneWidget);
    expect(popped, isTrue, reason: 'back on Today, which asks again');
  });

  testWidgets('a syllabus topic picked is sent, to be ticked off for the class', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Decimals intro');
    await tester.tap(find.byKey(const Key('report-syllabus-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decimals').last);
    await tester.pumpAndSettle();
    await submit(tester);

    expect(reports.lastStorePayload!['syllabus_topic_id'], 102);
  });

  testWidgets('a second report for the period is refused in plain words, and the form stays', (tester) async {
    reports.failStoreWith = const Failure(
      code: 'TEACHING_REPORT_ALREADY_SUBMITTED',
      message: 'A report has already been submitted for this period and date.',
    );
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await submit(tester);

    expect(find.byKey(const Key('report-problem')), findsOneWidget);
    expect(find.textContaining('This period already has a report for 10/26/2026'), findsOneWidget);
    expect(popped, isFalse);
    expect(find.text('Fractions'), findsOneWidget, reason: 'what was typed is kept');
  });

  testWidgets('without signal it says nothing was sent', (tester) async {
    reports.failStoreWith = Failure.network();
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await submit(tester);

    expect(find.textContaining('No connection. Nothing was sent'), findsOneWidget);
  });

  testWidgets('a period no longer theirs is explained', (tester) async {
    reports.failStoreWith = const Failure(code: 'FORBIDDEN', message: 'This action is unauthorized.');
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await submit(tester);

    expect(find.textContaining('no longer yours on the timetable'), findsOneWidget);
  });

  testWidgets('the server\'s own validation message is shown as it came', (tester) async {
    reports.failStoreWith = const Failure(
      code: 'VALIDATION_ERROR',
      message: 'The report date must fall on the day this period is scheduled (Monday).',
    );
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await submit(tester);

    expect(find.text('The report date must fall on the day this period is scheduled (Monday).'), findsOneWidget);
  });

  testWidgets('two quick taps file one report', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await tester.ensureVisible(find.byKey(const Key('report-submit')));
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.tap(find.byKey(const Key('report-submit')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(reports.reports, hasLength(1));
  });

  testWidgets('a syllabus that will not load does not stop the report, and says so', (tester) async {
    topics.failListWith = Failure.network();
    await pump(tester);

    expect(find.byKey(const Key('report-topics-unavailable')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await submit(tester);
    expect(reports.reports, hasLength(1));
  });

  testWidgets('a subject with no syllabus offers no topic choice', (tester) async {
    topics = FakeSyllabusTopicRepository();
    await pump(tester);

    expect(find.byKey(const Key('report-syllabus-topic')), findsNothing);
    expect(find.byKey(const Key('report-topics-unavailable')), findsNothing);
  });

  testWidgets('without the subject from the server, no topic choice is offered', (tester) async {
    await pump(
      tester,
      given: const ReportPeriod(
        timetableEntryId: 11,
        date: '2026-10-26',
        classSection: 'Grade 3 A',
        subject: 'Mathematics',
        periodNumber: 1,
      ),
    );

    expect(find.byKey(const Key('report-syllabus-topic')), findsNothing);
  });

  testWidgets('fits a phone in the dark theme', (tester) async {
    await pump(tester, theme: AppTheme.teacherDark());
    await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('report-submit')), findsOneWidget);
  });
}
