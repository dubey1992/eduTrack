import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/home_widget/home_screen_widget.dart';
import 'package:edutrack_app/core/home_widget/today_card.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/family/application/family_today_card.dart';
import 'package:edutrack_app/features/family/data/family_repository.dart';
import 'package:edutrack_app/features/family/data/models/family_day.dart'
    show AttendanceMark, BusTrip, NextFee, TodayBus;
import 'package:edutrack_app/features/home_widget/today_widget_refresh.dart';
import 'package:edutrack_app/features/home_widget/today_widget_sync.dart';
import 'package:edutrack_app/features/today/application/staff_today_card.dart';
import 'package:edutrack_app/features/today/data/models/teacher_day.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_token_storage.dart';
import '../../support/fake_check_in_repository.dart';
import '../../support/fake_family_repositories.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';

/// The home-screen widget (docs/mobile-apps-review.md, M10, 6.1): what it
/// says for a teacher and for a parent, that it hides everything while the
/// app lock is on or nobody is signed in, and when it is refreshed.
class FakeHomeScreenWidget implements HomeScreenWidget {
  final List<TodayCard> shown = [];
  final Map<String, String?> saved = {};

  @override
  Future<void> show(TodayCard card) async => shown.add(card);

  @override
  Future<void> remember(String key, String? value) async => saved[key] = value;

  @override
  Future<String?> recall(String key) async => saved[key];
}

class FakeScheduler implements TodayWidgetScheduler {
  final List<String> calls = [];

  @override
  Future<void> start(String app) async => calls.add('start $app');

  @override
  Future<void> stop() async => calls.add('stop');
}

final at1105 = DateTime(2026, 10, 26, 11, 5);

void main() {
  group('the card', () {
    test('every line is written, so a shorter card leaves no stale line', () {
      const card = TodayCard(title: 'Today', lines: ['One'], asOf: 'as of 9:40 AM');

      expect(card.toWidgetData(), {
        'today_state': 'today',
        'today_title': 'Today',
        'today_line1': 'One',
        'today_line2': '',
        'today_line3': '',
        'today_line4': '',
        'today_as_of': 'as of 9:40 AM',
      });
    });

    test('locked and signed out say nothing about the day', () {
      expect(const TodayCard.locked().lines, ['Tap to open']);
      expect(const TodayCard.signedOut().lines, ['Sign in to see your day']);
      expect(const TodayCard.locked().asOf, isNull);
    });
  });

  group("a teacher's card", () {
    test('the period now, the register, the reports owed and checking in', () {
      final card = staffTodayCard(teacherDay(), notCheckedIn(), at1105);

      expect(card.title, 'Today');
      expect(card.lines, [
        'Now: P3 Science · Grade 9 A',
        'Register not taken: Grade 8 A',
        '1 report owed',
        'Not checked in yet',
      ]);
      expect(card.asOf, 'as of 11:05 AM');
    });

    test('between periods, the next one and when', () {
      final periods = [
        for (final p in samplePeriods)
          TodayPeriod(
            timetableEntryId: p.timetableEntryId,
            periodNumber: p.periodNumber,
            startTime: p.startTime,
            endTime: p.endTime,
            state: p.periodNumber == 3 ? PeriodState.done : p.state,
            classSectionId: p.classSectionId,
            classSection: p.classSection,
            subject: p.subject,
            reportFiled: p.reportFiled,
            reportId: p.reportId,
          ),
      ];

      expect(staffTodayCard(teacherDay(periods: periods), null, at1105).lines.first, startsWith('Next: P5'));
    });

    test('all done reads as done', () {
      final card = staffTodayCard(
        teacherDay(
          registers: const [ClassRegister(classSectionId: 81, classSection: 'Grade 8 A', submitted: true)],
          reportsOwed: 0,
        ),
        attendanceDay(checkIn: '08:45'),
        at1105,
      );

      expect(card.lines.sublist(1), ['Register taken', 'Reports up to date', 'Checked in at 8:45 AM']);
    });

    test('a school without check-in has no check-in line', () {
      expect(staffTodayCard(teacherDay(), attendanceDay(enabled: false), at1105).lines, hasLength(3));
      expect(staffTodayCard(teacherDay(), null, at1105).lines, hasLength(3));
    });

    test('a holiday says so, and nothing else', () {
      final card = staffTodayCard(teacherDay(isOpen: false, holidayName: 'Diwali'), null, at1105);

      expect(card.lines, ['Holiday: Diwali']);
    });

    test('a day on leave says so', () {
      final leave = LeaveSpan(
        id: 1,
        leaveType: 'casual',
        startDate: DateTime(2026, 10, 26),
        endDate: DateTime(2026, 10, 26),
      );

      expect(staffTodayCard(teacherDay(leaveToday: leave), null, at1105).lines, ['You are on leave today']);
    });
  });

  group("a parent's card", () {
    test("the child's register, the bus with its time, and the next fee", () {
      final today = familyToday(
        bus: const TodayBus(
          route: 'Green Park',
          stop: 'Lake View',
          pickupTime: '07:40',
          dropTime: '15:10',
          trips: [
            BusTrip(
              direction: 'pickup',
              status: 'in_progress',
              riderStatus: 'boarded',
              boardedAt: '07:42',
              droppedAt: null,
            ),
          ],
        ),
        fee: NextFee(
          label: 'Term 2',
          dueDate: DateTime(2026, 11, 30),
          amount: 2500,
          currencyCode: 'INR',
          isOverdue: false,
        ),
      );

      final card = familyTodayCard('Aarav', today, at1105);

      expect(card.title, 'Aarav');
      expect(card.lines[0], 'Today: Present');
      expect(card.lines[1], 'Bus: On the bus to school, 7:42 AM');
      expect(card.lines[2], 'Fees: ${formatCurrency(2500, 'INR')} due 11/30/2026');
    });

    test('before the bus runs, the pick-up time; an overdue fee says overdue', () {
      final today = familyToday(
        mark: AttendanceMark.notMarked,
        bus: const TodayBus(route: 'Green Park', stop: null, pickupTime: '07:40', dropTime: null, trips: []),
        fee: NextFee(
          label: 'Term 1',
          dueDate: DateTime(2026, 10, 1),
          amount: 900,
          currencyCode: 'INR',
          isOverdue: true,
        ),
      );

      final lines = familyTodayCard('Aarav', today, at1105).lines;

      expect(lines, ['Today: Not marked yet', 'Bus pick-up 7:40 AM', startsWith('Fees: ')]);
      expect(lines.last, endsWith('overdue'));
    });

    test('no school today says so, with the holiday', () {
      expect(familyTodayCard('Aarav', familyToday(isOpen: false, holiday: 'Diwali'), at1105).lines, [
        'No school today: Diwali',
      ]);
    });
  });

  group('the refresh', () {
    late FakeHomeScreenWidget widget;
    late FakeAuthTokenStorage tokens;
    late InMemoryKeyValueStore store;

    ProviderContainer container({
      FakeTodayRepository? today,
      FakeCheckInRepository? checkIn,
      FakeFamilyRepository? family,
    }) {
      final c = ProviderContainer(
        overrides: [
          homeScreenWidgetProvider.overrideWithValue(widget),
          authTokenStorageProvider.overrideWithValue(tokens),
          keyValueStoreProvider.overrideWithValue(store),
          todayRepositoryProvider.overrideWithValue(today ?? FakeTodayRepository()),
          checkInRepositoryProvider.overrideWithValue(checkIn ?? FakeCheckInRepository()),
          familyRepositoryProvider.overrideWithValue(family ?? FakeFamilyRepository()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() async {
      widget = FakeHomeScreenWidget();
      tokens = FakeAuthTokenStorage();
      store = InMemoryKeyValueStore();
      await tokens.saveToken('token');
    });

    test("signed in: the teacher's day goes on the home screen", () async {
      final c = container();

      await refreshTodayWidget(c.read, staffWidgetApp, at1105);

      expect(widget.shown.single.lines.first, 'Now: P3 Science · Grade 9 A');
    });

    test('nobody signed in: "Sign in", and nothing is fetched', () async {
      await tokens.clearToken();
      final today = FakeTodayRepository();

      await refreshTodayWidget(container(today: today).read, staffWidgetApp, at1105);

      expect(widget.shown.single.state, TodayCardState.signedOut);
      expect(today.calls, 0);
    });

    test('app lock on: "Tap to open", and nothing is fetched', () async {
      await store.write('app_lock.enabled', 'yes');
      final today = FakeTodayRepository();

      await refreshTodayWidget(container(today: today).read, staffWidgetApp, at1105);

      expect(widget.shown.single.state, TodayCardState.locked);
      expect(today.calls, 0);
    });

    test('a session the server ended: "Sign in"', () async {
      final today = FakeTodayRepository(
        failWith: const Failure(code: 'UNAUTHENTICATED', message: 'Signed out.'),
      );

      await refreshTodayWidget(container(today: today).read, staffWidgetApp, at1105);

      expect(widget.shown.single.state, TodayCardState.signedOut);
    });

    test('no signal: the last card stays up, with its time', () async {
      await refreshTodayWidget(
        container(today: FakeTodayRepository(failWith: Failure.network())).read,
        staffWidgetApp,
        at1105,
      );

      expect(widget.shown, isEmpty);
    });

    test('check-in that cannot be read leaves out its line only', () async {
      final c = container(checkIn: FakeCheckInRepository(failLoadWith: Failure.network()));

      await refreshTodayWidget(c.read, staffWidgetApp, at1105);

      expect(widget.shown.single.lines, hasLength(3));
    });

    test("the parent's card is about the child the app last showed", () async {
      widget.saved[widgetChildIdKey] = '${aarav.id}';
      widget.saved[widgetChildNameKey] = 'Aarav';

      await refreshTodayWidget(container().read, familyWidgetApp, at1105);

      expect(widget.shown.single.title, 'Aarav');
      expect(widget.shown.single.lines.first, 'Today: Present');
    });

    test('before the Family app has said which child, nothing changes', () async {
      await refreshTodayWidget(container().read, familyWidgetApp, at1105);

      expect(widget.shown, isEmpty);
    });
  });

  group('kept in step with the app', () {
    late FakeHomeScreenWidget widget;
    late FakeScheduler scheduler;
    late FakeAuthTokenStorage tokens;

    Future<void> pump(WidgetTester tester, bool? signedIn) async {
      final overrides = <Override>[
        homeScreenWidgetProvider.overrideWithValue(widget),
        todayWidgetSchedulerProvider.overrideWithValue(scheduler),
        authTokenStorageProvider.overrideWithValue(tokens),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            home: TodayWidgetSync(app: staffWidgetApp, signedIn: signedIn, child: const Text('app')),
          ),
        ),
      );
      await tester.pump();
    }

    setUp(() async {
      widget = FakeHomeScreenWidget();
      scheduler = FakeScheduler();
      tokens = FakeAuthTokenStorage();
      await tokens.saveToken('token');
    });

    testWidgets('signed in: the half-hourly job starts and the card is drawn', (tester) async {
      await pump(tester, true);
      await tester.pump(const Duration(seconds: 2));

      expect(scheduler.calls, ['start staff']);
      expect(widget.shown.single.state, TodayCardState.today);
    });

    testWidgets('signing out stops the job and leaves "Sign in" on the home screen', (tester) async {
      await pump(tester, true);
      await tester.pump(const Duration(seconds: 2));
      await tokens.clearToken();

      await pump(tester, false);

      expect(scheduler.calls, ['start staff', 'stop']);
      expect(widget.shown.last.state, TodayCardState.signedOut);
    });

    testWidgets('while the session is still being read, nothing happens', (tester) async {
      await pump(tester, null);
      await tester.pump(const Duration(seconds: 2));

      expect(scheduler.calls, isEmpty);
      expect(widget.shown, isEmpty);
    });

    testWidgets('a start with nobody signed in clears the widget', (tester) async {
      await pump(tester, false);

      expect(scheduler.calls, ['stop']);
      expect(widget.shown.single.state, TodayCardState.signedOut);
    });
  });
}
