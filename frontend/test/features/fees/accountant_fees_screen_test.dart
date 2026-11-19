import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/features/academic_years/application/academic_year_picker_provider.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/data/models/fee_receipt.dart';
import 'package:edutrack_app/features/fees/presentation/accountant_fees_screen.dart';
import 'package:edutrack_app/features/fees/presentation/widgets/student_statement_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_fee_repository.dart';
import '../../support/session_users.dart';

/// The accountant's Fees tab in the Staff app (docs/mobile-apps-review.md,
/// 7.2): collect, today, overdue - and a student's statement over it.
AcademicYear _year() => AcademicYear(
  id: 1,
  schoolId: 1,
  schoolName: 'Green Valley',
  name: '2026-27',
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: true,
);

void main() {
  late FakeFeeRepository fees;
  late List<Uri> dialled;

  setUp(() {
    fees = FakeFeeRepository()
      ..balanceRows = [fakeBalance()]
      ..statements = {7: fakeStatement()}
      ..receiptRows = [
        fakeReceipt(id: 70, amount: '2000.00'),
        fakeReceipt(id: 71, amount: '1500.00', mode: PaymentMode.upi),
        fakeReceipt(id: 72, amount: '500.00'),
      ];
    dialled = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/fees',
      routes: [
        GoRoute(
          path: '/fees',
          builder: (context, state) => const Scaffold(body: AccountantFeesScreen()),
        ),
        GoRoute(
          path: '/fees/students/:id',
          builder: (context, state) => Scaffold(
            body: StudentStatementView(
              studentId: int.parse(state.pathParameters['id']!),
              onBack: () => context.pop(),
              canManage: true,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feeRepositoryProvider.overrideWithValue(fees),
          academicYearPickerProvider.overrideWith((ref, arg) async => [_year()]),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.accountant)),
          ),
          feesDiallerProvider.overrideWithValue((uri) async {
            dialled.add(uri);
            return true;
          }),
        ],
        child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key('fees-tab-$key')));
    await tester.pumpAndSettle();
  }

  testWidgets("Collect finds the student paying, in this year, and opens their statement", (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const Key('fees-collect-search')), 'asha');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fees.balanceQueries.last, containsPair('search', 'asha'));
    expect(fees.balanceQueries.last, containsPair('academic_year_id', 1));
    expect(find.text('Asha Rao'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fees-student-7')));
    await tester.pumpAndSettle();

    expect(find.byType(StudentStatementView), findsOneWidget);
    expect(find.text('Record Payment'), findsOneWidget, reason: 'the statement itself, not its error');
    expect(tester.takeException(), isNull, reason: 'the statement fits a phone');
  });

  testWidgets('a payment is recorded from the statement on a phone, with the receipt to follow', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('fees-collect-search')), 'asha');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fees-student-7')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Record Payment'));
    await tester.tap(find.text('Record Payment'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Amount received'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the payment form fits a phone');

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '2000');
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();

    expect(fees.payments.single['amount'], '2000.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets("Today totals the day's receipts in its currency and by how they were paid", (tester) async {
    await pump(tester);
    await openTab(tester, 'today');

    final asked = fees.receiptQueries.last;
    expect(asked['from'], isNotNull);
    expect(asked['from'], asked['to'], reason: 'one day');
    expect(asked['cancelled'], isFalse);

    final totals = find.byKey(const Key('fees-today-totals'));
    expect(find.descendant(of: totals, matching: find.text('3 receipts today')), findsOneWidget);
    expect(find.descendant(of: totals, matching: find.text(formatCurrency(4000, 'INR'))), findsOneWidget);
    expect(
      find.descendant(of: totals, matching: find.text(formatCurrency(2500, 'INR'))),
      findsOneWidget,
      reason: 'cash',
    );
    expect(
      find.descendant(of: totals, matching: find.text(formatCurrency(1500, 'INR'))),
      findsOneWidget,
      reason: 'UPI',
    );
  });

  testWidgets('a day with nothing collected says so', (tester) async {
    fees.receiptRows = [];
    await pump(tester);
    await openTab(tester, 'today');

    expect(find.byKey(const Key('fees-today-empty')), findsOneWidget);
  });

  testWidgets('Overdue lists who is late, with the guardian one tap away', (tester) async {
    await pump(tester);
    await openTab(tester, 'overdue');

    expect(fees.balanceQueries.last, containsPair('overdue', true));
    expect(find.text('1 student with fees overdue'), findsOneWidget);
    expect(find.textContaining('Overdue ${formatCurrency(2000, 'INR')}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fees-call-7')));
    await tester.pumpAndSettle();

    expect(dialled.single.toString(), 'tel:+919876543210');
  });
}
