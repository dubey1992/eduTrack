import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/data/models/dashboard.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_links.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/session_users.dart';

/// The dashboard enhancement (docs/dashboard.md): quick actions, cards that
/// open their page, today's money per person, and this month's messages.

final _admin = sessionUser(UserRole.schoolAdmin, id: 2, name: 'Anita Sharma');

const _collections = CollectionsToday(
  date: '2026-09-14',
  receipts: 3,
  cancelledReceipts: 1,
  collected: ['INR 3,950.00'],
  byStaff: [
    StaffCollection(
      receivedById: 7,
      receivedBy: 'Rahul Sharma',
      receipts: 2,
      amount: 'INR 3,550.00',
      cash: 'INR 3,550.00',
      credit: 'INR 250.00',
      hasCredit: true,
    ),
    StaffCollection(
      receivedById: null,
      receivedBy: 'Not recorded',
      receipts: 1,
      amount: 'INR 400.00',
      cash: 'INR 0.00',
      credit: 'INR 0.00',
      hasCredit: false,
    ),
  ],
);

const _messages = MessagesThisMonth(
  month: 'September 2026',
  total: MessageCounts(channel: 'all', label: 'SMS and WhatsApp', sent: 210, queued: 20, failed: 10, skipped: 4),
  channels: [
    MessageCounts(channel: 'sms', label: 'SMS', sent: 150, queued: 20, failed: 6, skipped: 4),
    MessageCounts(channel: 'whatsapp', label: 'WhatsApp', sent: 60, queued: 0, failed: 4, skipped: 0),
  ],
  feeRelated: 35,
  providerDelivers: true,
);

Dashboard _withSections({CollectionsToday? collections = _collections, MessagesThisMonth? messages = _messages}) {
  return Dashboard(
    role: defaultDashboard.role,
    asOf: defaultDashboard.asOf,
    isWorkingDay: true,
    holiday: null,
    schoolId: 1,
    cards: [
      ...defaultDashboard.cards,
      const DashboardCard(
        key: 'fees_collected',
        label: 'Fees collected this month',
        value: 'INR 3,950.00',
        hint: '3 receipts',
        tone: 'neutral',
      ),
      const DashboardCard(key: 'unknown_figure', label: 'Something new', value: '4', hint: null, tone: 'neutral'),
    ],
    attendanceTrend: const [],
    attention: const [],
    collectionsToday: collections,
    messagesThisMonth: messages,
  );
}

/// The dashboard inside a router whose every other page just says where it
/// was opened, so a test can read where a tap went.
Widget _app(Dashboard dashboard, {AuthenticatedUser? actor}) {
  Widget opened(BuildContext context, GoRouterState state) => Scaffold(body: Text('opened ${state.uri}'));

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: DashboardScreen()),
      ),
      for (final path in [
        '/reports',
        '/students',
        '/staff',
        '/attendance',
        '/student-fees',
        '/fee-receipts',
        '/communication',
        '/payroll',
      ])
        GoRoute(path: path, builder: opened),
    ],
  );

  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository(dashboard: dashboard)),
      analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor ?? _admin)),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('quick actions', () {
    testWidgets('an admin gets the office jobs, each one click away', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      for (final label in [
        'Collect fees',
        'Collection report',
        'Receipts',
        'Find a student',
        'Messages',
        'Fees owed',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No date lock: the app has none, so no button promises one.
      expect(find.textContaining('Date lock'), findsNothing);

      await _tapAndSettle(tester, find.byKey(const Key('quick-action-collection-report')));
      expect(find.text('opened /reports?report=fee-collection&from=2026-09-14&to=2026-09-14'), findsOneWidget);
    });

    testWidgets('the student search opens the students list', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      await _tapAndSettle(tester, find.byKey(const Key('quick-action-students')));
      expect(find.text('opened /students'), findsOneWidget);
    });

    testWidgets('a teacher is offered none of the fee or message jobs', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(
        _app(_withSections(collections: null, messages: null), actor: sessionUser(UserRole.teacher)),
      );
      await tester.pumpAndSettle();

      for (final key in ['collect', 'collection-report', 'receipts', 'messages', 'outstanding']) {
        expect(find.byKey(Key('quick-action-$key')), findsNothing, reason: key);
      }
    });

    testWidgets('with fees switched off the fee jobs go, the rest stay', (tester) async {
      _desktop(tester);
      final admin = sessionUser(UserRole.schoolAdmin, modules: {AppModules.fees: false});
      await tester.pumpWidget(_app(_withSections(collections: null), actor: admin));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quick-action-collect')), findsNothing);
      expect(find.byKey(const Key('quick-action-collection-report')), findsNothing);
      expect(find.byKey(const Key('quick-action-students')), findsOneWidget);
      expect(find.byKey(const Key('quick-action-messages')), findsOneWidget);
    });

    testWidgets('the matrix decides: fees at none removes them for an accountant too', (tester) async {
      _desktop(tester);
      final accountant = sessionUser(
        UserRole.accountant,
        permissions: {...allModulesAt(PermissionLevel.none), AppModules.fees: PermissionLevel.none},
      );
      await tester.pumpWidget(_app(_withSections(collections: null, messages: null), actor: accountant));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quick-action-collect')), findsNothing);
    });
  });

  group('cards open their page', () {
    testWidgets('the students card opens the student list', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      await _tapAndSettle(tester, find.byKey(const Key('stat-card-link-students')));
      expect(find.text('opened /students'), findsOneWidget);
    });

    testWidgets("fees collected opens this month's collection report", (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      await _tapAndSettle(tester, find.byKey(const Key('stat-card-link-fees_collected')));
      expect(find.text('opened /reports?report=fee-collection&from=2026-09-01&to=2026-09-14'), findsOneWidget);
    });

    testWidgets('a figure with no page, or a page the person may not open, is not a link', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections(), actor: sessionUser(UserRole.teacher)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stat-card-unknown_figure')), findsOneWidget);
      expect(find.byKey(const Key('stat-card-link-unknown_figure')), findsNothing);
      // A teacher cannot open the staff list or the fee reports.
      expect(find.byKey(const Key('stat-card-link-staff')), findsNothing);
      expect(find.byKey(const Key('stat-card-link-fees_collected')), findsNothing);
    });
  });

  group('collected today, by person', () {
    testWidgets('each person with their receipts, cash and credit, and the cancelled count', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('INR 3,550.00'), findsOneWidget);
      expect(find.text('2 receipts - cash INR 3,550.00 - held as credit INR 250.00'), findsOneWidget);
      expect(find.textContaining('1 cancelled not counted'), findsOneWidget);
      expect(find.textContaining('Held as credit is part of the amount'), findsOneWidget);
    });

    testWidgets("a person's line opens the report narrowed to them", (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      await _tapAndSettle(tester, find.byKey(const Key('collections-person-7')));
      expect(
        find.text(
          'opened /reports?report=fee-collection&from=2026-09-14&to=2026-09-14'
          '&received_by=7&received_by_name=Rahul+Sharma',
        ),
        findsOneWidget,
      );
    });

    testWidgets('receipts with nobody recorded are shown but not narrowed to', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      final line = tester.widget<ListTile>(find.byKey(const Key('collections-person-unknown')));
      expect(line.onTap, isNull);
    });

    testWidgets('a quiet day says so', (tester) async {
      _desktop(tester);
      const quiet = CollectionsToday(
        date: '2026-09-14',
        receipts: 0,
        cancelledReceipts: 0,
        collected: ['INR 0.00'],
        byStaff: [],
      );
      await tester.pumpWidget(_app(_withSections(collections: quiet)));
      await tester.pumpAndSettle();

      expect(find.text('No fees have been collected yet today.'), findsOneWidget);
    });

    testWidgets('nothing at all when the server sends no section', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections(collections: null, messages: null)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-collections-today')), findsNothing);
      expect(find.byKey(const Key('dashboard-messages')), findsNothing);
    });
  });

  group('messages this month', () {
    testWidgets('counts by the status the log keeps, and never claims delivery', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_app(_withSections()));
      await tester.pumpAndSettle();

      expect(find.text('SMS & WhatsApp - September 2026'), findsOneWidget);
      expect(find.text('244 messages, 35 about fees'), findsOneWidget);
      expect(find.text('Sent to provider'), findsOneWidget);
      expect(find.text('210'), findsOneWidget);
      expect(find.text('WhatsApp: 60 sent, 0 waiting, 4 failed, 0 not sent'), findsOneWidget);
      expect(find.textContaining('Delivered'), findsNothing);
      expect(find.textContaining('Delivery to the phone is not reported back'), findsOneWidget);

      await _tapAndSettle(tester, find.byKey(const Key('messages-open-log')));
      expect(find.text('opened /communication'), findsOneWidget);
    });

    testWidgets('with delivery reports, shows what reached the phone and what did not', (tester) async {
      _desktop(tester);
      const reported = MessagesThisMonth(
        month: 'September 2026',
        total: MessageCounts(
          channel: 'all',
          label: 'SMS and WhatsApp',
          sent: 210,
          queued: 0,
          failed: 0,
          skipped: 0,
          delivered: 190,
          undelivered: 7,
        ),
        channels: [
          MessageCounts(
            channel: 'sms',
            label: 'SMS',
            sent: 210,
            queued: 0,
            failed: 0,
            skipped: 0,
            delivered: 190,
            undelivered: 7,
          ),
        ],
        feeRelated: 0,
        providerDelivers: true,
        deliveryReported: true,
      );
      await tester.pumpWidget(_app(_withSections(messages: reported)));
      await tester.pumpAndSettle();

      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('190'), findsOneWidget);
      expect(find.text('Not delivered'), findsOneWidget);
      expect(
        find.text('SMS: 210 sent (190 delivered, 7 not delivered), 0 waiting, 0 failed, 0 not sent'),
        findsOneWidget,
      );
      expect(find.textContaining('A sent message with no report yet is in neither'), findsOneWidget);
    });

    testWidgets('says plainly when SMS is going nowhere', (tester) async {
      _desktop(tester);
      const nowhere = MessagesThisMonth(
        month: 'September 2026',
        total: MessageCounts(channel: 'all', label: 'SMS and WhatsApp', sent: 3, queued: 0, failed: 0, skipped: 0),
        channels: [],
        feeRelated: 0,
        providerDelivers: false,
      );
      await tester.pumpWidget(_app(_withSections(messages: nowhere)));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not reach phones'), findsOneWidget);
    });
  });

  testWidgets('on a phone the panels stack without overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_withSections()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final collections = tester.getTopLeft(find.byKey(const Key('dashboard-collections-today')));
    final messages = tester.getTopLeft(find.byKey(const Key('dashboard-messages')));
    expect(messages.dy, greaterThan(collections.dy), reason: 'one above the other');
    // Quick-action tiles fill the line rather than leaving a gap beside them.
    final tile = tester.getSize(find.byKey(const Key('quick-action-collect')));
    final panel = tester.getSize(find.byKey(const Key('dashboard-quick-actions')));
    expect(tile.width, greaterThan(panel.width - 40));
  });

  test('the sections are read from the payload, and absent ones are null', () {
    final dashboard = Dashboard.fromJson({
      'role': 'SCHOOL_ADMIN',
      'as_of': '2026-09-14',
      'collections_today': {
        'date': '2026-09-14',
        'receipts': 1,
        'cancelled_receipts': 0,
        'collected': ['INR 400.00'],
        'by_staff': [
          {
            'received_by_id': 7,
            'received_by': 'Rahul Sharma',
            'receipts': 1,
            'amount': '400.00',
            'credit_amount': '0.00',
            'amount_display': 'INR 400.00',
            'cash_display': 'INR 0.00',
            'credit_display': 'INR 0.00',
          },
        ],
      },
      'messages_this_month': null,
    });

    expect(dashboard.collectionsToday!.byStaff.single.receivedBy, 'Rahul Sharma');
    expect(dashboard.collectionsToday!.byStaff.single.hasCredit, isFalse);
    expect(dashboard.messagesThisMonth, isNull);
  });

  test("a branch's figures open that branch's reports", () {
    final today = DateTime(2026, 9, 14);

    expect(
      linkForCard('fees_collected', today, schoolId: 420)!.location,
      '/reports?report=fee-collection&school_id=420&from=2026-09-01&to=2026-09-14',
    );
    expect(linkForCard('fees_overdue', today)!.location, '/reports?report=fee-outstanding');
    // Pages that are not reports take no school.
    expect(linkForCard('students', today, schoolId: 420)!.location, '/students');
    expect(linkForCard('something_new', today), isNull);
    // The roll by gender opens the student list.
    for (final key in ['boys', 'girls', 'gender_other']) {
      expect(linkForCard(key, today)!.location, '/students', reason: key);
    }
  });
}
