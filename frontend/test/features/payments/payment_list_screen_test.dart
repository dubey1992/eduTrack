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

final _payment = Payment(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  paymentType: PaymentType.setupFee,
  amount: 25000,
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
    expect(find.text('PMT-000001'), findsOneWidget);
  });
}
