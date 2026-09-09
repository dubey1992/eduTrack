import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:edutrack_app/features/payments/presentation/edit_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';

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
    overrides: [paymentRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditPaymentDialog(payment: _payment),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a validation error when the amount is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakePaymentRepository(payments: [_payment])));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount'), findsOneWidget);
  });

  testWidgets('updates the payment, closes the dialog, and shows a confirmation snackbar', (tester) async {
    final fake = FakePaymentRepository(payments: [_payment]);
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '30000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list();
    expect(updated.single.amount, 30000);
    expect(find.byType(EditPaymentDialog), findsNothing);
    expect(find.text('Payment updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open when the repository throws', (tester) async {
    final fake = FakePaymentRepository(
      payments: [_payment],
      failUpdateWith: const Failure(code: 'PAYMENT_UPDATE_FAILED', message: 'Could not update the payment.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '30000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not update the payment.'), findsOneWidget);
    expect(find.byType(EditPaymentDialog), findsOneWidget);
  });
}
