import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/early_warning.dart';
import 'package:edutrack_app/features/analytics/presentation/early_warning_screen.dart';
import 'package:edutrack_app/features/analytics/presentation/widgets/early_warning_banner.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/session_users.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 5, name: 'Rahul Verma', email: 'rahul@example.com', role: UserRole.teacher);
const _root = AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin);

Widget _wrap(FakeAnalyticsRepository fake, Widget child, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      analyticsRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('reads a page: the students, their reasons and the whole list\'s counts', () {
    final page = fakeEarlyWarningPage(high: 1, atRisk: 1);

    expect(page.students.map((s) => s.level), [EarlyWarningLevel.high, EarlyWarningLevel.atRisk]);
    expect(page.students.first.signals.first.isAttendance, isTrue);
    expect(page.students.first.signals.last.previous, 71);
    expect((page.summary.attendanceBelow, page.summary.passMark, page.summary.dropPoints), (75, 33, 10));
    expect(page.summary.flaggedCount, 2);
  });

  group('the list', () {
    testWidgets('each student with their level and the server\'s own reasons', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(FakeAnalyticsRepository(flaggedHigh: 1, flaggedAtRisk: 1), const EarlyWarningScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zara Khan'), findsOneWidget);
      expect(find.text('High risk'), findsOneWidget);
      expect(find.text('Attendance 62% over the last 30 school days, below 75%.'), findsOneWidget);
      expect(find.text('Test average down 23 points, from 71% to 48%.'), findsOneWidget);
      expect(find.text('At risk'), findsOneWidget);
      expect(find.text('All flagged (2)'), findsOneWidget);
      // The lines it was drawn with, stated.
      expect(find.textContaining('under the 33% pass mark'), findsOneWidget);
    });

    testWidgets('a level chip asks the server for that level', (tester) async {
      _tall(tester);
      final fake = FakeAnalyticsRepository(flaggedHigh: 1, flaggedAtRisk: 1);
      await tester.pumpWidget(_wrap(fake, const EarlyWarningScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('High risk (1)'));
      await tester.pumpAndSettle();

      expect(fake.earlyWarningAsked.last.level, EarlyWarningLevel.high);
      expect(find.text('Arjun Kumar'), findsNothing);
    });

    testWidgets('opens on the level the dashboard asked for', (tester) async {
      _tall(tester);
      final fake = FakeAnalyticsRepository(flaggedHigh: 1, flaggedAtRisk: 1);
      await tester.pumpWidget(_wrap(fake, const EarlyWarningScreen(initialLevel: EarlyWarningLevel.high)));
      await tester.pumpAndSettle();

      expect(fake.earlyWarningAsked.single.level, EarlyWarningLevel.high);
    });

    testWidgets('nobody flagged says so, with the drop it looked for', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(FakeAnalyticsRepository(), const EarlyWarningScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('No students are flagged.'), findsOneWidget);
    });

    testWidgets("a refusal shows the server's message with a retry", (tester) async {
      _tall(tester);
      final fake = FakeAnalyticsRepository(
        earlyWarningFailure: const Failure(
          code: 'MODULE_DISABLED',
          message: 'Reports is switched off for this school.',
        ),
      );
      await tester.pumpWidget(_wrap(fake, const EarlyWarningScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Reports is switched off for this school.'), findsOneWidget);
    });

    testWidgets('a class teacher is told it is their class', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(FakeAnalyticsRepository(), const EarlyWarningScreen(), actor: _teacher));
      await tester.pumpAndSettle();

      expect(find.textContaining('Students in your class'), findsOneWidget);
    });

    testWidgets('a Super Admin picks a school before anything is asked', (tester) async {
      _tall(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const EarlyWarningScreen(), actor: _root));
      await tester.pumpAndSettle();

      expect(find.text('Pick a school to see its students.'), findsOneWidget);
      expect(fake.earlyWarningAsked, isEmpty);
    });
  });

  group('the dashboard banner', () {
    testWidgets('counts the flagged students and asks for one row only', (tester) async {
      final fake = FakeAnalyticsRepository(flaggedHigh: 3, flaggedAtRisk: 8);
      await tester.pumpWidget(_wrap(fake, const EarlyWarningBanner(schoolId: null)));
      await tester.pumpAndSettle();

      expect(find.text('3 students at high risk, 8 at risk'), findsOneWidget);
      expect(fake.earlyWarningAsked.single.perPage, 1);
    });

    testWidgets('says nothing when nobody is flagged', (tester) async {
      await tester.pumpWidget(_wrap(FakeAnalyticsRepository(), const EarlyWarningBanner(schoolId: null)));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('says nothing when it cannot load', (tester) async {
      final fake = FakeAnalyticsRepository(
        earlyWarningFailure: const Failure(code: 'X', message: 'Down.'),
      );
      await tester.pumpWidget(_wrap(fake, const EarlyWarningBanner(schoolId: null)));
      await tester.pumpAndSettle();

      expect(find.text('Down.'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('Review opens the high-risk list', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: EarlyWarningBanner(schoolId: null)),
          ),
          GoRoute(path: '/early-warning', builder: (context, state) => Text('opened ${state.uri}')),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository(flaggedHigh: 1)),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('opened /early-warning?level=high'), findsOneWidget);
    });

    testWidgets('is not shown to a role without early warning', (tester) async {
      final fake = FakeAnalyticsRepository(flaggedHigh: 1);
      await tester.pumpWidget(
        _wrap(
          fake,
          const EarlyWarningBanner(schoolId: null),
          actor: const AuthenticatedUser(id: 9, name: 'Sam', email: 'sam@example.com', role: UserRole.accountant),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.earlyWarningAsked, isEmpty);
    });
  });

  group('the menu entry', () {
    final item = AppNav.findByPath('/early-warning')!;

    test('admins, heads of department and teachers - nobody else', () {
      for (final role in [UserRole.schoolAdmin, UserRole.groupAdmin, UserRole.hod, UserRole.teacher]) {
        expect(item.allows(sessionUser(role)), isTrue, reason: role.name);
      }
      for (final role in [UserRole.staff, UserRole.accountant, UserRole.transportManager, UserRole.driver]) {
        expect(item.allows(sessionUser(role)), isFalse, reason: role.name);
      }
    });

    test('gone where the school has Reports switched off', () {
      expect(item.allows(sessionUser(UserRole.teacher, modules: {AppModules.reports: false})), isFalse);
    });
  });
}
