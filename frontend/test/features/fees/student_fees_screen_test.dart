import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/presentation/student_fees_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_academic_term_repository.dart';
import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_fee_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_school_repository.dart';
import 'fee_setup_screen_test.dart' show class8;

late GoRouter _router;

String get location => _router.routerDelegate.currentConfiguration.uri.toString();

Widget wrap(FakeFeeRepository fees, {String at = '/student-fees', UserRole role = UserRole.accountant}) {
  _router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: '/student-fees',
        builder: (context, state) =>
            Scaffold(body: StudentFeesScreen(studentId: int.tryParse(state.uri.queryParameters['student'] ?? ''))),
      ),
    ],
  );

  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      feeRepositoryProvider.overrideWithValue(fees),
      academicYearRepositoryProvider.overrideWithValue(FakeAcademicYearRepository(years: [fakeYear()])),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [class8])),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 9, name: 'Meena', email: 'm@example.com', role: role),
        ),
      ),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: _router),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Text that may sit beside a currency symbol drawn with a no-break space.
Finder money(String figure) => find.textContaining(figure);

void main() {
  group('the list', () {
    testWidgets('each student with what they were charged, paid and still owe', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..balanceRows = [fakeBalance()];
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.textContaining('ADM-007 · Class 8 - A · next due 11/10/2026'), findsOneWidget);
      expect(money('24,000.00'), findsOneWidget);
      expect(money('20,000.00'), findsOneWidget);
      // "4,000.00" is also inside "24,000.00": the balance and the charge.
      expect(money('4,000.00'), findsNWidgets(2));
      expect(fees.balanceQueries.single['academic_year_id'], 1);
    });

    testWidgets('"Owing only" asks the server, and starts again from page one', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..balanceRows = [fakeBalance(balance: '0.00', overdue: '0.00')];
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Owing only'));
      await tester.pumpAndSettle();

      expect(fees.balanceQueries.last['owing'], isTrue);
      expect(fees.balanceQueries.last['page'], 1);
      expect(find.text('No student matches these filters.'), findsOneWidget);
    });

    testWidgets('a search reaches the server', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..balanceRows = [fakeBalance()];
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'asha');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(fees.balanceQueries.last['search'], 'asha');
    });

    testWidgets('a year nobody has been charged for says how charging happens', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository()));
      await tester.pumpAndSettle();

      expect(find.textContaining('No student has been charged for 2026-27 yet'), findsOneWidget);
    });

    testWidgets('a list that cannot be read offers a retry', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..failWith = Failure.network();
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);

      fees
        ..failWith = null
        ..balanceRows = [fakeBalance()];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Asha Rao'), findsOneWidget);
    });

    testWidgets('a student opens their statement, and Back returns to the list', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()
        ..balanceRows = [fakeBalance()]
        ..statements = {7: fakeStatement()};
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asha Rao'));
      await tester.pumpAndSettle();
      expect(location, '/student-fees?student=7');
      expect(find.text('Tuition - May 2026'), findsOneWidget);

      await tester.tap(find.text('All students'));
      await tester.pumpAndSettle();
      expect(location, '/student-fees');
    });

    testWidgets('a super admin chooses a school first', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(), role: UserRole.superAdmin));
      await tester.pumpAndSettle();

      expect(find.text('Choose a school to see its fees.'), findsOneWidget);
    });
  });

  group('the statement', () {
    testWidgets('shows the totals, and every installment with where it stands', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..statements = {7: fakeStatement()};
      await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7'));
      await tester.pumpAndSettle();

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Charged'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Paid'), findsWidgets);
      // The overdue installment says so, the paid one too.
      expect(find.text('Tuition - May 2026'), findsOneWidget);
      expect(find.text('Due 05/10/2026'), findsOneWidget);
    });

    testWidgets('an installment no longer charged is shown struck through, with why', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..statements = {7: fakeStatement()};
      await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining('not charged: moved to another bus route'), findsOneWidget);

      final label = tester.widget<Text>(find.text('Transport - Term 2'));
      expect(label.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a student the server cannot find is an error with a retry, not a blank page', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(), at: '/student-fees?student=99'));
      await tester.pumpAndSettle();

      expect(find.text('The requested resource was not found.'), findsOneWidget);
      expect(find.text('All students'), findsOneWidget);
    });
  });
}
