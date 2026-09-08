import 'package:edutrack_app/features/payments/application/payment_list_notifier.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';

Payment _payment({PaymentStatus status = PaymentStatus.paid}) {
  return Payment(
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
    status: status,
    createdByName: 'Test Admin',
  );
}

void main() {
  ProviderContainer makeContainer(FakePaymentRepository fake) {
    return ProviderContainer(overrides: [paymentRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial payment list', () async {
    final container = makeContainer(FakePaymentRepository(payments: [_payment()]));
    addTearDown(container.dispose);

    final result = await container.read(paymentListNotifierProvider.future);

    expect(result, hasLength(1));
    expect(result.first.amount, 25000);
  });

  test('createPayment() adds the new payment to the list', () async {
    final container = makeContainer(FakePaymentRepository());
    addTearDown(container.dispose);
    await container.read(paymentListNotifierProvider.future);

    await container
        .read(paymentListNotifierProvider.notifier)
        .createPayment(
          schoolId: 1,
          paymentType: PaymentType.annualMaintenance,
          amount: 5000,
          paymentDate: DateTime(2026, 9, 5),
          paymentMode: PaymentMode.cash,
          status: PaymentStatus.pending,
        );

    final state = container.read(paymentListNotifierProvider).value;
    expect(state, hasLength(1));
    expect(state!.first.status, PaymentStatus.pending);
  });

  test('updateStatus() updates that payment in place', () async {
    final container = makeContainer(
      FakePaymentRepository(payments: [_payment(status: PaymentStatus.pending)]),
    );
    addTearDown(container.dispose);
    final payments = await container.read(paymentListNotifierProvider.future);

    await container
        .read(paymentListNotifierProvider.notifier)
        .updateStatus(payments.first, PaymentStatus.paid);

    final state = container.read(paymentListNotifierProvider).value;
    expect(state!.first.status, PaymentStatus.paid);
  });
}
