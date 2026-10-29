import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/finance_overview.dart';
import 'package:edutrack_app/features/analytics/presentation/analytics_screen.dart';
import 'package:edutrack_app/features/analytics/presentation/widgets/finance_view.dart';
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
const _hod = AuthenticatedUser(id: 4, name: 'Ravi', email: 'ravi@example.com', role: UserRole.hod);

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
    _wrap(fake, const SingleChildScrollView(child: FinanceView(schoolId: null)));

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('reads every section, one line per currency, and knows when payroll is withheld', () {
    final overview = FinanceOverview.fromJson(fakeFinanceJson());
    final july = overview.collection.last;

    expect(overview.currencies, ['INR', 'USD']);
    expect((july.currency('INR')!['due'], july.currency('INR')!['collected']), (1000.0, 1000.0));
    expect(july.currency('USD')!.rate, 25.0);
    expect(overview.overdueByAge.first.amounts, isNull);
    expect(overview.byClass.single.amounts['outstanding'], 1000.0);
    expect(overview.feesVsPayroll, isNotNull);
    expect(FinanceOverview.fromJson(fakeFinanceJson(withPayroll: false)).feesVsPayroll, isNull);
  });

  group('the view', () {
    testWidgets('a block per currency, never one total across them', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('In INR'), findsOneWidget);
      expect(find.text('In USD'), findsOneWidget);
      expect(find.text('Collected by month'), findsNWidgets(2));
      expect(find.text(formatCurrency(40, 'USD')), findsOneWidget);
    });

    testWidgets('shows each section with its figures', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository()));
      await tester.pumpAndSettle();

      // Falling due next: October's scheduled 1,000.
      expect(find.text('Oct 2026'), findsWidgets);
      // Overdue by age: July recorded, June not shown.
      // In each currency's block: a recorded night with no USD line means none owed in USD.
      expect(find.text('Jul 2026 (07/15/2026)'), findsNWidgets(2));
      expect(find.text(formatCurrency(750, 'INR')), findsOneWidget);
      // By class.
      expect(find.text('Class 8 A'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      // Fees and payroll: 1,000 in, 800 out.
      expect(find.text('Fees and payroll'), findsNWidgets(2));
      expect(find.text(formatCurrency(200, 'INR')), findsOneWidget);
    });

    testWidgets('without payroll access the payroll section is not there', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository(financeJson: fakeFinanceJson(withPayroll: false))));
      await tester.pumpAndSettle();

      expect(find.text('Fees and payroll'), findsNothing);
      expect(find.text('Collected by month'), findsWidgets);
    });

    testWidgets('a school with no fee money says so', (tester) async {
      _tall(tester);
      final empty = {
        ...fakeFinanceJson(withPayroll: false),
        'collection': <dynamic>[],
        'overdue_by_age': <dynamic>[],
        'by_class': <dynamic>[],
        'upcoming': <dynamic>[],
      };
      await tester.pumpWidget(_view(FakeAnalyticsRepository(financeJson: empty)));
      await tester.pumpAndSettle();

      expect(find.text('No fees have been charged or collected in the last twelve months.'), findsOneWidget);
    });

    testWidgets("a refusal shows the server's message", (tester) async {
      _tall(tester);
      final fake = FakeAnalyticsRepository(
        failure: const Failure(code: 'MODULE_DISABLED', message: 'Fee Management is switched off.'),
      );
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      expect(find.text('Fee Management is switched off.'), findsOneWidget);
    });
  });

  group('on the Analytics page', () {
    testWidgets('an admin opens Finance', (tester) async {
      _tall(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const AnalyticsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finance'));
      await tester.pumpAndSettle();

      expect(fake.financeAsked, hasLength(1));
      expect(find.text('Collected by month'), findsWidgets);
    });

    testWidgets('a head of department, who reads no fees, is not offered it', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(FakeAnalyticsRepository(), const AnalyticsScreen(), actor: _hod));
      await tester.pumpAndSettle();

      expect(find.text('Finance'), findsNothing);
      expect(find.text('Subjects & classes'), findsOneWidget);
    });
  });
}
