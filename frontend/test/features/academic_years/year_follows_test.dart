import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/application/viewed_year.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/application/dashboard_notifier.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/viewed_year_overrides.dart';

const _admin = AuthenticatedUser(
  id: 2,
  name: 'Anita',
  email: 'anita@example.com',
  role: UserRole.schoolAdmin,
  schoolId: 1,
);

AcademicYear _year(String name, int start, {bool current = false}) => AcademicYear(
  id: start,
  schoolId: 1,
  schoolName: 'Sunrise',
  name: name,
  startDate: DateTime(start, 4, 1),
  endDate: DateTime(start + 1, 3, 31),
  isCurrent: current,
);

/// What follows the top bar's year beyond the lists (decided 2026-11-05):
/// Reports, Analytics and the dashboard's trends and results.
void main() {
  group('the period a past year stands for', () {
    final today = DateTime(2026, 11, 5);

    test('a past year is the whole of it', () {
      final period = yearPeriod(_year('2025-26', 2025), today)!;

      expect((period.from, period.to), (DateTime(2025, 4, 1), DateTime(2026, 3, 31)));
    });

    test('the current year keeps each screen default', () {
      expect(yearPeriod(_year('2026-27', 2026, current: true), today), isNull);
    });

    test('a year not begun has nothing to show', () {
      expect(yearPeriod(_year('2027-28', 2027), today), isNull);
    });

    test('no year at all keeps the default', () {
      expect(yearPeriod(null, today), isNull);
    });
  });

  test('the dashboard asks for the year in view, and again when it changes', () async {
    final fake = FakeDashboardRepository();
    final container = ProviderContainer(
      overrides: [dashboardRepositoryProvider.overrideWithValue(fake), ...viewedYearIs(null)],
    );
    addTearDown(container.dispose);

    await container.read(dashboardNotifierProvider.future);
    expect(fake.lastYearId, isNull);

    await container.read(viewedYearIdProvider.notifier).choose(2025);
    await container.read(dashboardNotifierProvider.future);

    expect(fake.lastYearId, 2025);
  });

  testWidgets('the dashboard says which year it shows, and its trends name it', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
          schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
          ...viewedYearIs(_year('2025-26', 2025)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-year-note')), findsOneWidget);
    expect(find.textContaining('Showing 2025-26'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('trends-title'))).data, startsWith('Trends, 2025-26'));
  });

  testWidgets('the current year shows no note and the last six months', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
          schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
          ...viewedYearIs(_year('2026-27', 2026, current: true)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-year-note')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('trends-title'))).data, 'Trends, last 6 months');
  });
}
