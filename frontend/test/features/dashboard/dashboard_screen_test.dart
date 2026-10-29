import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/data/models/dashboard.dart';
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

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeDashboardRepository fake, {AuthenticatedUser actor = _admin, FakeAnalyticsRepository? analytics}) {
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(fake),
      analyticsRepositoryProvider.overrideWithValue(analytics ?? FakeAnalyticsRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: DashboardScreen()),
    ),
  );
}

/// Phase 18's landing screen.
///
/// The server decides which figures a role gets, so these check that whatever
/// arrives is rendered honestly - particularly the two states that are easy to
/// misread: a day with no register, and a day the school was shut.
void main() {
  testWidgets('shows the cards the server sent', (tester) async {
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Students'), findsOneWidget);
    expect(find.text('842'), findsOneWidget);
    expect(find.text('Attendance today'), findsOneWidget);
    expect(find.text('94.8%'), findsOneWidget);
  });

  testWidgets('money in several currencies gets a line each, and every card in the row is level', (tester) async {
    // It used to print "INR 2,002,000.00 + NGN 45,000.01 + USD 1,234.50" at
    // headline size, wrapping mid-amount and making the card twice as tall as
    // its neighbours.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeDashboardRepository(dashboard: moneyDashboard)));
    await tester.pumpAndSettle();

    expect(find.text('INR 2,002,000.00'), findsOneWidget);
    expect(find.text('NGN 45,000.01'), findsOneWidget);
    expect(find.text('USD 1,234.50'), findsOneWidget);
    expect(find.textContaining(' + '), findsNothing);
    expect(tester.takeException(), isNull, reason: 'no overflow');

    final heights = [
      for (final label in ['Schools', 'Collected', 'Payments owing'])
        tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(Card)).first).height,
    ];
    expect(heights.toSet(), hasLength(1), reason: 'card heights were $heights');

    // No line wraps: every currency is one line tall.
    expect(tester.getSize(find.text('INR 2,002,000.00')).height, tester.getSize(find.text('USD 1,234.50')).height);
  });

  testWidgets('a single large amount shrinks to fit rather than wrapping', (tester) async {
    const dashboard = Dashboard(
      role: 'SUPER_ADMIN',
      asOf: '2026-09-17',
      isWorkingDay: false,
      holiday: null,
      schoolId: null,
      cards: [
        DashboardCard(
          key: 'collected',
          label: 'Collected',
          value: 'INR 123,456,789,012.00',
          hint: 'money received',
          tone: 'neutral',
        ),
      ],
      attendanceTrend: [],
      attention: [],
    );

    await tester.pumpWidget(wrap(FakeDashboardRepository(dashboard: dashboard)));
    await tester.pumpAndSettle();

    final line = find.text('INR 123,456,789,012.00');
    expect(line, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(line).height, lessThan(40), reason: 'one line, not wrapped');
  });

  testWidgets('lists what needs attention', (tester) async {
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('No attendance has been marked yet today.'), findsOneWidget);
  });

  testWidgets('says the school is closed rather than showing an empty day', (tester) async {
    // On a holiday "nothing marked" is the expected state, not a lapse - and
    // the banner has to say so or somebody will go chasing it.
    await tester.pumpWidget(wrap(FakeDashboardRepository(dashboard: holidayDashboard)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Founders Day'), findsOneWidget);
    expect(find.textContaining('the school is closed today'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('does not claim the school is shut when no school is in scope', (tester) async {
    // A Super Admin across seven schools has no single set of opening hours,
    // so "the school is closed today" would be nonsense.
    await tester.pumpWidget(wrap(FakeDashboardRepository(dashboard: platformDashboard)));
    await tester.pumpAndSettle();

    expect(find.textContaining('the school is closed'), findsNothing);
    expect(find.text('Schools'), findsOneWidget);
  });

  testWidgets('draws a day with no register as a dash, never as zero', (tester) async {
    // A zero bar would read as every child being absent.
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('95%'), findsOneWidget);
    expect(find.text('71%'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('shows an error with a retry when the figures cannot be loaded', (tester) async {
    final fake = FakeDashboardRepository(
      failWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);

    fake.failWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('842'), findsOneWidget);
  });

  testWidgets('refreshing re-reads the figures', (tester) async {
    // They describe today, and a tab left open outlives today.
    final fake = FakeDashboardRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(fake.fetchCalls, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
    await tester.pumpAndSettle();

    expect(fake.fetchCalls, 2);
  });

  testWidgets('offers the reports to a role that has them', (tester) async {
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Open reports'), findsOneWidget);
  });

  testWidgets('does not offer reports to a teacher', (tester) async {
    const teacher = AuthenticatedUser(id: 9, name: 'Priya', email: 'p@example.com', role: UserRole.teacher);
    await tester.pumpWidget(wrap(FakeDashboardRepository(), actor: teacher));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Open reports'), findsNothing);
  });

  group('trends', () {
    testWidgets('shows the featured figures with their latest value, and gaps as gaps', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final analytics = FakeAnalyticsRepository();

      await tester.pumpWidget(wrap(FakeDashboardRepository(), analytics: analytics));
      await tester.pumpAndSettle();

      expect(find.text('Trends, last 6 months'), findsOneWidget);
      // Attendance: the latest month, and its change on the last month that
      // had a register - August had none.
      expect(find.text('88%'), findsOneWidget);
      expect(find.text('-3.5 pts on the month before'), findsOneWidget);
      // Money: the first currency charted, the other said, never added.
      expect(find.text(formatCurrency(400, 'INR')), findsOneWidget);
      expect(find.textContaining('+1 more currency'), findsOneWidget);
      // Not recorded yet: said, not drawn as nought.
      expect(find.text('Recorded daily from now on - no figures yet.'), findsOneWidget);
      // Six months, ending today at the school.
      expect(analytics.asked.map((a) => a.measure).toSet(), {
        'student_attendance_rate',
        'fees_collected',
        'active_students',
      });
    });

    testWidgets('a card opens its full chart on the analytics page', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: DashboardScreen()),
          ),
          GoRoute(path: '/analytics', builder: (context, state) => Text('opened ${state.uri}')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
            schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fees collected'));
      await tester.pumpAndSettle();

      expect(find.text('opened /analytics?measure=fees_collected'), findsOneWidget);
    });

    testWidgets('a trend that fails says so in one line and offers a retry', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final analytics = FakeAnalyticsRepository(
        failure: const Failure(code: 'X', message: 'Could not reach the server.'),
      );

      await tester.pumpWidget(wrap(FakeDashboardRepository(), analytics: analytics));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server.'), findsNWidgets(3));
      await tester.tap(find.text('Retry').first);
      await tester.pumpAndSettle();
      expect(analytics.asked.length, 4);
    });

    testWidgets("a group admin on the whole group sees their own school's trends, named", (tester) async {
      final analytics = FakeAnalyticsRepository();
      await tester.pumpWidget(
        wrap(
          FakeDashboardRepository(),
          analytics: analytics,
          actor: const AuthenticatedUser(
            id: 7,
            name: 'Group',
            email: 'group@example.com',
            role: UserRole.groupAdmin,
            schoolId: 1,
            managesBranches: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Their own school, not a prompt to pick one.
      expect(analytics.asked.map((a) => a.schoolId).toSet(), {1});
      expect(find.text('Pick a school above to see its trends.'), findsNothing);
    });

    testWidgets('a role without analytics sees no trends', (tester) async {
      await tester.pumpWidget(
        wrap(
          FakeDashboardRepository(),
          actor: const AuthenticatedUser(id: 5, name: 'Ravi', email: 'ravi@example.com', role: UserRole.teacher),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trends, last 6 months'), findsNothing);
    });

    testWidgets('a Super Admin picks a school first', (tester) async {
      final analytics = FakeAnalyticsRepository();
      await tester.pumpWidget(
        wrap(
          FakeDashboardRepository(),
          analytics: analytics,
          actor: const AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pick a school above to see its trends.'), findsOneWidget);
      expect(analytics.asked, isEmpty);
    });
  });
}
