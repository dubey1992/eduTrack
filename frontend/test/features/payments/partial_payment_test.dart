import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:edutrack_app/features/payments/presentation/edit_payment_dialog.dart';
import 'package:edutrack_app/features/payments/presentation/payment_receipt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';

Payment payment({
  double amount = 50000,
  double paidAmount = 20000,
  PaymentStatus status = PaymentStatus.partial,
  String? receiptSentAt,
}) {
  return Payment(
    id: 1,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    paymentType: PaymentType.annualMaintenance,
    amount: amount,
    paidAmount: paidAmount,
    remainingAmount: status == PaymentStatus.cancelled ? 0 : amount - paidAmount,
    currencyCode: 'INR',
    paymentDate: DateTime(2026, 9, 1),
    paymentMode: PaymentMode.bankTransfer,
    referenceNumber: 'NEFT-771',
    notes: null,
    status: status,
    createdByName: 'Super Admin',
    receiptSentAt: receiptSentAt,
  );
}

Widget wrap(FakePaymentRepository fake, Widget child) {
  return ProviderScope(
    overrides: [paymentRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => child),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Part-payments: what is still owed has to be stated, not left as a
/// subtraction between two numbers on the screen.
void main() {
  group('the receipt view', () {
    testWidgets('states the balance due on a part-payment', (tester) async {
      final p = payment();
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), PaymentReceiptDialog(payment: p)));
      await open(tester);

      expect(find.textContaining('Balance due'), findsOneWidget);
      expect(find.textContaining('30,000.00'), findsWidgets);
      expect(find.text('Partially Paid'), findsOneWidget);
    });

    testWidgets('shows no balance line once a payment is settled', (tester) async {
      final p = payment(paidAmount: 50000, status: PaymentStatus.paid);
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), PaymentReceiptDialog(payment: p)));
      await open(tester);

      expect(find.textContaining('Balance due'), findsNothing);
    });

    testWidgets('a cancelled payment owes nothing', (tester) async {
      final p = payment(status: PaymentStatus.cancelled);
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), PaymentReceiptDialog(payment: p)));
      await open(tester);

      expect(find.textContaining('Balance due'), findsNothing);
    });

    testWidgets('emails the receipt on request and says so', (tester) async {
      final p = payment();
      final fake = FakePaymentRepository(payments: [p]);
      await tester.pumpWidget(wrap(fake, PaymentReceiptDialog(payment: p)));
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Email receipt'));
      await tester.pumpAndSettle();

      expect(fake.sendReceiptCalls, 1);
      expect(find.text('Receipt emailed to the school admins.'), findsOneWidget);
    });

    testWidgets('offers to send again once one has gone out', (tester) async {
      final p = payment(receiptSentAt: '2026-09-13T10:00:00Z');
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), PaymentReceiptDialog(payment: p)));
      await open(tester);

      expect(find.widgetWithText(FilledButton, 'Email again'), findsOneWidget);
    });
  });

  group('the edit form', () {
    testWidgets('asks how much was received only for a part-payment', (tester) async {
      final p = payment(paidAmount: 50000, status: PaymentStatus.paid);
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), EditPaymentDialog(payment: p)));
      await open(tester);

      expect(find.widgetWithText(TextFormField, 'Amount received'), findsNothing);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<PaymentStatus>, 'Paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partially Paid').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Amount received'), findsOneWidget);
    });

    testWidgets('works out what remains as the figure is typed', (tester) async {
      final p = payment();
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), EditPaymentDialog(payment: p)));
      await open(tester);

      expect(find.textContaining('Remaining'), findsOneWidget);
      expect(find.textContaining('30,000.00'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '45000');
      await tester.pumpAndSettle();

      expect(find.textContaining('5,000.00'), findsWidgets);
    });

    testWidgets('refuses a received amount larger than the payment', (tester) async {
      final p = payment();
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), EditPaymentDialog(payment: p)));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '60000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('This is more than the payment amount'), findsOneWidget);
    });

    testWidgets('points at Paid when the whole amount has been received', (tester) async {
      // "Partial" and "all of it" contradict each other; the form says so
      // rather than quietly recording a partial payment with no balance.
      final p = payment();
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [p]), EditPaymentDialog(payment: p)));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '50000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Received in full - choose Paid instead'), findsOneWidget);
    });

    testWidgets('sends the received amount when saved', (tester) async {
      final p = payment();
      final fake = FakePaymentRepository(payments: [p]);
      await tester.pumpWidget(wrap(fake, EditPaymentDialog(payment: p)));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '35000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = (await fake.list()).first;
      expect(saved.paidAmount, 35000);
      expect(saved.remainingAmount, 15000);
      expect(saved.status, PaymentStatus.partial);
    });
  });
}
