import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/platform_overview.dart';
import 'package:edutrack_app/features/analytics/presentation/analytics_screen.dart';
import 'package:edutrack_app/features/analytics/presentation/widgets/platform_view.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';

const _root = AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin);
const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget _wrap(FakeAnalyticsRepository fake, Widget child, {AuthenticatedUser actor = _root}) {
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

Widget _view(FakeAnalyticsRepository fake) => _wrap(fake, const SingleChildScrollView(child: PlatformView()));

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2800, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('reads the totals, each month, each school and the modules', () {
    final overview = PlatformOverview.fromJson(fakePlatformJson());
    final september = overview.months.last;

    expect((overview.totals.schoolsActive, overview.totals.students), (2, 420));
    expect((september.signIns, september.activeUsers), (75, 18));
    expect(september.messages['sms'], (sent: 120, failed: 4));
    expect(september.payments.map((p) => p.currencyCode), ['INR', 'NGN']);
    expect(overview.totals.schoolsNotCounted, 4);
    expect(overview.modules.single.schoolsOn, 1);
  });

  test('a school row says its category, and how a trial stands', () {
    final rows = fakePlatformSchools().map(PlatformSchool.fromJson).toList();

    expect(rows.map((row) => row.categoryText), ['Live', 'In Trial - ended 09/01/2026', 'Demo']);
    expect(rows[1].lastSignInLabel, isNull);
  });

  group('the view', () {
    testWidgets('totals, months newest first, schools and modules', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Active schools'), findsOneWidget);
      expect(find.text('420'), findsOneWidget);

      final months = find.textContaining(RegExp(r'^(Aug|Sep) 2026$'));
      expect(tester.widget<Text>(months.first).data, 'Sep 2026');
      expect(find.text('120 (4 failed)'), findsOneWidget);
      expect(find.text('30'), findsWidgets);

      expect(find.text('Demo & testing (not counted)'), findsOneWidget);
      expect(find.text('Sunrise School, Pune'), findsOneWidget);
      expect(find.text('09/12/2026'), findsOneWidget);
      expect(find.text('Never'), findsNWidgets(2));
      expect(find.text('In Trial - ended 09/01/2026'), findsOneWidget);
      expect(find.text('Show School'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
    });

    testWidgets('the school list asks for one category, from page one', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('platform-schools-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo').last);
      await tester.pumpAndSettle();

      expect((fake.platformSchoolsAsked.last.category, fake.platformSchoolsAsked.last.page), ('demo', 1));
      expect(find.text('Sunrise School, Pune'), findsNothing);
      expect(find.text('Show School'), findsOneWidget);
    });

    testWidgets('a search is sent once typing stops', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('platform-schools-search')), 'lagos');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(fake.platformSchoolsAsked.last.q, 'lagos');
      expect(find.text('Lagos Academy, Lagos'), findsOneWidget);
      expect(find.text('Sunrise School, Pune'), findsNothing);
    });

    testWidgets('payments stay apart, one line per currency', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository()));
      await tester.pumpAndSettle();

      final payments = find.textContaining('50,000');
      expect(payments, findsOneWidget);
      final text = tester.widget<Text>(payments).data!;
      expect(text.split('\n'), hasLength(2));
      expect(text, contains('300,000.00'));
    });

    testWidgets('a platform with no schools says so', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository(platformSchoolRows: [])));
      await tester.pumpAndSettle();

      expect(find.text('There are no schools yet.'), findsOneWidget);
    });

    testWidgets("a refusal shows the server's message", (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository(
        failure: const Failure(code: 'FORBIDDEN', message: 'You are not allowed to do this.'),
      );
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      expect(find.text('You are not allowed to do this.'), findsOneWidget);
    });
  });

  group('on the Analytics page', () {
    testWidgets('the Super Admin lands on Platform, with no school to pick first', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const AnalyticsScreen()));
      await tester.pumpAndSettle();

      expect(fake.platformAsked, 1);
      expect(find.text('Each school'), findsOneWidget);
      expect(find.text('Trends'), findsOneWidget);
    });

    testWidgets('a school admin is not offered it', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const AnalyticsScreen(), actor: _admin));
      await tester.pumpAndSettle();

      expect(find.text('Platform'), findsNothing);
      expect(fake.platformAsked, 0);
    });
  });
}
