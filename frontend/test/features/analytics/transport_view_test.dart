import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/transport_overview.dart';
import 'package:edutrack_app/features/analytics/presentation/analytics_screen.dart';
import 'package:edutrack_app/features/analytics/presentation/widgets/transport_view.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);
const _manager = AuthenticatedUser(id: 6, name: 'Vikram', email: 'vikram@example.com', role: UserRole.transportManager);
const _accountant = AuthenticatedUser(id: 9, name: 'Sam', email: 'sam@example.com', role: UserRole.accountant);

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

Widget _view(FakeAnalyticsRepository fake) =>
    _wrap(fake, const SingleChildScrollView(child: TransportView(schoolId: null)));

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('reads each route month by month and the late stops', () {
    final overview = TransportOverview.fromJson(fakeTransportJson());
    final september = overview.routes.single.months.last;

    expect(overview.lateAfterMinutes, 10);
    expect((september.daysRun, september.workingDays, september.tripsCancelled), (2, 10, 1));
    expect((september.boarded, september.ridersOnList, september.boardedRate), (3, 4, 75.0));
    expect((september.onTimeRate, september.averageMinutesLate), (66.7, 16.0));
    expect(overview.routes.single.months.first.averageMinutes, isNull);
    expect(overview.lateStops.single.stop, 'Market');
  });

  group('the view', () {
    testWidgets('the stops most often late, then each route month by month', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Stops most often late'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
      expect(find.textContaining('more than 10 minutes after'), findsOneWidget);

      expect(find.text('Route A'), findsWidgets);
      expect(find.text('2 of 10'), findsOneWidget);
      expect(find.text('3 of 4 (75%)'), findsOneWidget);
      expect(find.text('66.7% of 3'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
    });

    testWidgets('a school with no routes says so', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository(transportJson: fakeTransportJson(withRoutes: false))));
      await tester.pumpAndSettle();

      expect(find.text('This school has no routes yet.'), findsOneWidget);
    });

    testWidgets("a refusal shows the server's message", (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository(
        failure: const Failure(code: 'MODULE_DISABLED', message: 'Transport is off.'),
      );
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      expect(find.text('Transport is off.'), findsOneWidget);
    });
  });

  group('on the Analytics page', () {
    testWidgets('a transport manager lands on Transport, with no trends to offer', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const AnalyticsScreen(), actor: _manager));
      await tester.pumpAndSettle();

      expect(fake.transportAsked, hasLength(1));
      expect(find.text('Stops most often late'), findsOneWidget);
      expect(find.text('Trends'), findsNothing);
      expect(find.text('Finance'), findsNothing);
    });

    testWidgets('an admin has Transport among the views', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const AnalyticsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();

      expect(fake.transportAsked, hasLength(1));
    });

    testWidgets('an accountant is not offered it', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_wrap(FakeAnalyticsRepository(), const AnalyticsScreen(), actor: _accountant));
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsNothing);
    });
  });
}
