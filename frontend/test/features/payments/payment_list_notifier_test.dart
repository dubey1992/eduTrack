import 'package:edutrack_app/features/payments/application/payment_list_notifier.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';

Payment _payment({
  int id = 1,
  int schoolId = 1,
  String schoolName = 'Sunrise Public School',
  PaymentStatus status = PaymentStatus.paid,
}) {
  return Payment(
    id: id,
    schoolId: schoolId,
    schoolName: schoolName,
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

  test('build() loads the initial page of payments', () async {
    final container = makeContainer(FakePaymentRepository(payments: [_payment()]));
    addTearDown(container.dispose);

    final result = await container.read(paymentListNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.amount, 25000);
  });

  test('createPayment() adds the new payment and returns to page 1', () async {
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
    expect(state!.items, hasLength(1));
    expect(state.items.first.status, PaymentStatus.pending);
  });

  test('setSchoolFilter() narrows the list down to that school only', () async {
    final schoolA = _payment(id: 1, schoolId: 1, schoolName: 'Sunrise Public School');
    final schoolB = _payment(id: 2, schoolId: 2, schoolName: 'Green Valley School');
    final container = makeContainer(FakePaymentRepository(payments: [schoolA, schoolB]));
    addTearDown(container.dispose);
    final all = await container.read(paymentListNotifierProvider.future);
    expect(all.items, hasLength(2));

    await container.read(paymentListNotifierProvider.notifier).setSchoolFilter(2);

    final filtered = container.read(paymentListNotifierProvider).value;
    expect(filtered!.items, hasLength(1));
    expect(filtered.items.first.schoolId, 2);

    await container.read(paymentListNotifierProvider.notifier).setSchoolFilter(null);

    final cleared = container.read(paymentListNotifierProvider).value;
    expect(cleared!.items, hasLength(2));
  });

  test('updatePayment() saves the changes in place', () async {
    final container = makeContainer(FakePaymentRepository(payments: [_payment()]));
    addTearDown(container.dispose);
    final page = await container.read(paymentListNotifierProvider.future);

    await container
        .read(paymentListNotifierProvider.notifier)
        .updatePayment(page.items.first, amount: 30000, referenceNumber: 'TXN-2');

    final state = container.read(paymentListNotifierProvider).value;
    expect(state!.items.first.amount, 30000);
    expect(state.items.first.referenceNumber, 'TXN-2');
  });

  test('updateStatus() updates that payment in place', () async {
    final container = makeContainer(FakePaymentRepository(payments: [_payment(status: PaymentStatus.pending)]));
    addTearDown(container.dispose);
    final page = await container.read(paymentListNotifierProvider.future);

    await container.read(paymentListNotifierProvider.notifier).updateStatus(page.items.first, PaymentStatus.paid);

    final state = container.read(paymentListNotifierProvider).value;
    expect(state!.items.first.status, PaymentStatus.paid);
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(FakePaymentRepository(payments: [for (var i = 1; i <= 25; i++) _payment(id: i)]));
    addTearDown(container.dispose);
    await container.read(paymentListNotifierProvider.future);

    await container.read(paymentListNotifierProvider.notifier).goToPage(2);
    var state = container.read(paymentListNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(paymentListNotifierProvider.notifier).setPerPage(50);
    state = container.read(paymentListNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}
