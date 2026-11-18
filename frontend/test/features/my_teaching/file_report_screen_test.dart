import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_teaching/data/report_notes.dart';
import 'package:edutrack_app/features/my_teaching/presentation/file_report_screen.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_syllabus_topic_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_today_repository.dart';
import 'teaching_fixtures.dart';

/// Filing a teaching report on the phone (docs/teacher-app.md, T3).
void main() {
  late FakeTeachingReportRepository reports;
  late FakeSyllabusTopicRepository topics;
  late bool popped;

  /// The phone's store, where drafts and templates are kept (1.6).
  late InMemoryKeyValueStore store;

  setUp(() {
    store = InMemoryKeyValueStore();
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
          keyValueStoreProvider.overrideWithValue(store),
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

  group('fewer taps (docs/mobile-apps-review.md, 1.6)', () {
    const withClass = ReportPeriod(
      timetableEntryId: 11,
      date: '2026-10-26',
      classSection: 'Grade 3 A',
      subject: 'Mathematics',
      periodNumber: 1,
      subjectId: 31,
      classSectionId: 5,
    );

    Future<void> typeAndPause(WidgetTester tester, Key field, String text) async {
      await tester.enterText(find.byKey(field), text);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('what is typed is kept as a draft, and is back when the form opens again', (tester) async {
      await pump(tester);
      await typeAndPause(tester, const Key('report-topic'), 'Fractions: halves');
      await typeAndPause(tester, const Key('report-homework'), 'Exercise 4.1');

      // Gone - a call came in - then opened again.
      await tester.pumpWidget(const SizedBox());
      await pump(tester);

      expect(find.text('Fractions: halves'), findsOneWidget);
      expect(find.text('Exercise 4.1'), findsOneWidget);
      expect(find.text('Your draft is back.'), findsOneWidget);
    });

    testWidgets('a report filed forgets its draft', (tester) async {
      await pump(tester);
      await typeAndPause(tester, const Key('report-topic'), 'Fractions: halves');
      await submit(tester);

      await pump(tester);

      expect(find.text('Fractions: halves'), findsNothing);
    });

    testWidgets("Same as last time copies the teacher's last report for this class and subject", (tester) async {
      reports = FakeTeachingReportRepository(
        reports: [report(date: '2026-10-23', topic: 'Fractions: like denominators', homework: 'Exercise 3.9')],
      );
      await pump(tester, given: withClass);

      expect(reports.lastListMine, isTrue);
      expect(reports.lastListClassAndSubject, (5, 31));
      expect(reports.lastListRange?.$2, '2026-10-25', reason: 'before the day being reported');

      await tester.tap(find.byKey(const Key('report-same-as-last')));
      await tester.pumpAndSettle();

      expect(find.text('Fractions: like denominators'), findsOneWidget);
      expect(find.text('Exercise 3.9'), findsOneWidget);
    });

    testWidgets('with no earlier report there is nothing to copy', (tester) async {
      await pump(tester, given: withClass);

      expect(find.byKey(const Key('report-same-as-last')), findsNothing);
    });

    testWidgets('a template saved for the subject fills the form later with one tap', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('report-templates')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-templates-empty')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('report-template-save'))).onPressed, isNull);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('report-topic')), 'Mental maths warm-up');
      await tester.tap(find.byKey(const Key('report-templates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-template-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-template-0')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('report-topic')), '');
      await tester.tap(find.byKey(const Key('report-templates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-template-0')));
      await tester.pumpAndSettle();

      expect(find.text('Mental maths warm-up'), findsOneWidget);
    });
  });

  group('the notes on the phone', () {
    test('templates are per subject, newest first, one copy of a topic, at most ten', () async {
      final notes = ReportNotes(InMemoryKeyValueStore());
      for (var i = 0; i < 12; i++) {
        await notes.saveTemplate(31, ReportWords(topic: 'Lesson $i'));
      }
      await notes.saveTemplate(31, const ReportWords(topic: 'Lesson 5'));
      await notes.saveTemplate(32, const ReportWords(topic: 'Other subject'));

      final kept = await notes.templates(31);
      expect(kept, hasLength(ReportNotes.maxTemplates));
      expect(kept.first.topic, 'Lesson 5');
      expect(kept.where((t) => t.topic == 'Lesson 5'), hasLength(1));
      expect((await notes.templates(32)).single.topic, 'Other subject');
    });

    test('signing out forgets drafts and templates', () async {
      final store = InMemoryKeyValueStore();
      final notes = ReportNotes(store);
      await notes.saveDraft(11, '2026-10-26', const ReportWords(topic: 'x'));
      await notes.saveTemplate(31, const ReportWords(topic: 'y'));

      await notes.clear();

      expect(await notes.draft(11, '2026-10-26'), isNull);
      expect(await notes.templates(31), isEmpty);
    });

    test('an unreadable store is notes lost, not a failure', () async {
      final store = InMemoryKeyValueStore();
      await store.write('report_drafts', 'not json');

      expect(await ReportNotes(store).draft(11, '2026-10-26'), isNull);
    });
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

  testWidgets("asks for the topics of this period's class only (decided 2026-11-05)", (tester) async {
    await pump(tester);

    expect(topics.lastListScope?.timetableEntryId, period.timetableEntryId);
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

  group('the teacher has not checked in today (decided 2026-11-02)', () {
    const notIn = Failure(
      code: 'CHECK_IN_REQUIRED',
      message: 'Check in first. Your teaching reports open once you are marked present today.',
    );

    testWidgets('says so, keeps what was typed, and offers the way back to check in', (tester) async {
      reports.failStoreWith = notIn;
      await pump(tester);
      await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
      await submit(tester);

      expect(find.textContaining('Check in first'), findsOneWidget);
      expect(find.text('Fractions'), findsOneWidget);
      expect(find.byKey(const Key('report-go-check-in')), findsOneWidget);
      expect(popped, isFalse);
    });

    testWidgets('the way back goes to Today without filing anything', (tester) async {
      reports.failStoreWith = notIn;
      await pump(tester);
      await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
      await submit(tester);

      await tester.tap(find.byKey(const Key('report-go-check-in')));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget, reason: 'back on Today');
      expect(popped, isFalse, reason: 'nothing was filed');
    });

    testWidgets('a leave refusal is shown as it came, with no check-in offered', (tester) async {
      reports.failStoreWith = const Failure(
        code: 'LEAVE_APPLIED',
        message: 'You have applied for leave today. Withdraw the request and check in to file reports for it.',
      );
      await pump(tester);
      await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
      await submit(tester);

      expect(find.textContaining('Withdraw the request'), findsOneWidget);
      expect(find.byKey(const Key('report-go-check-in')), findsNothing);
    });

    testWidgets('once a later try fails for another reason, the check-in offer is gone', (tester) async {
      reports.failStoreWith = notIn;
      await pump(tester);
      await tester.enterText(find.byKey(const Key('report-topic')), 'Fractions');
      await submit(tester);

      reports.failStoreWith = Failure.network();
      await submit(tester);

      expect(find.byKey(const Key('report-go-check-in')), findsNothing);
    });
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
