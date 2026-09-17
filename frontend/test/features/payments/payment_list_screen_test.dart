import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:edutrack_app/features/payments/presentation/payment_list_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/paginated_table.dart';

final _payment = Payment(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  paymentType: PaymentType.setupFee,
  amount: 25000,
  paidAmount: 25000,
  remainingAmount: 0,
  currencyCode: 'INR',
  paymentDate: DateTime(2026, 9, 1),
  paymentMode: PaymentMode.bankTransfer,
  referenceNumber: 'TXN-1',
  notes: null,
  status: PaymentStatus.paid,
  createdByName: 'Test Admin',
);

Widget wrap(FakePaymentRepository fake) {
  return ProviderScope(
    overrides: [
      paymentRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: PaymentListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no payments', (tester) async {
    await tester.pumpWidget(wrap(FakePaymentRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No payments recorded yet.'), findsOneWidget);
  });

  testWidgets('shows the total-collection KPI grouped by currency', (tester) async {
    final fake = FakePaymentRepository(
      payments: [_payment],
      summary: const PaymentSummary(
        totalByCurrency: [CurrencyTotal(currencyCode: 'INR', total: 25000)],
        monthlyByCurrency: [],
        pendingByCurrency: [],
        pendingCount: 0,
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining('Total Collection (INR)'), findsOneWidget);
    expect(find.text('Sunrise Public School'), findsOneWidget);
  });

  testWidgets('opens a receipt dialog when a payment row is tapped', (tester) async {
    await tester.pumpWidget(wrap(FakePaymentRepository(payments: [_payment])));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunrise Public School'));
    await tester.pumpAndSettle();

    expect(find.text('Payment Receipt'), findsOneWidget);
    expect(find.text('RCPT-000001'), findsOneWidget);
  });

  testWidgets('shows an error state with a retry button when the repository throws', (tester) async {
    final fake = FakePaymentRepository(
      failListPageWith: const Failure(code: 'PAYMENT_LIST_FAILED', message: 'Could not load payments.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load payments.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No payments recorded yet.'), findsOneWidget);
  });

  testWidgets('a full page of payments scrolls above the pagination bar on desktop', (tester) async {
    useShortDesktopWindow(tester);
    final payments = [
      for (var n = 1; n <= 20; n++)
        Payment(
          id: n,
          schoolId: n,
          schoolName: 'School $n',
          paymentType: PaymentType.setupFee,
          amount: 25000,
          paidAmount: 25000,
          remainingAmount: 0,
          currencyCode: 'INR',
          paymentDate: DateTime(2026, 9, 1),
          paymentMode: PaymentMode.bankTransfer,
          referenceNumber: 'TXN-$n',
          notes: null,
          status: PaymentStatus.paid,
          createdByName: 'Test Admin',
        ),
    ];
    await tester.pumpWidget(wrap(FakePaymentRepository(payments: payments)));
    await tester.pumpAndSettle();

    await expectLastRowScrollsAbovePagination(tester, find.text('School 20'));
  });
}
