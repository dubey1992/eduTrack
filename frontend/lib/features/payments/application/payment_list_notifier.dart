import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/payment.dart';
import '../data/payment_repository.dart';
import 'payment_summary_notifier.dart';

final paymentListNotifierProvider = AsyncNotifierProvider<PaymentListNotifier, List<Payment>>(
  PaymentListNotifier.new,
);

class PaymentListNotifier extends AsyncNotifier<List<Payment>> {
  @override
  Future<List<Payment>> build() {
    return ref.read(paymentRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(paymentRepositoryProvider).list());
  }

  Future<void> createPayment({
    required int schoolId,
    required PaymentType paymentType,
    required double amount,
    required DateTime paymentDate,
    required PaymentMode paymentMode,
    String? referenceNumber,
    String? notes,
    required PaymentStatus status,
  }) async {
    await ref
        .read(paymentRepositoryProvider)
        .create(
          schoolId: schoolId,
          paymentType: paymentType,
          amount: amount,
          paymentDate: paymentDate,
          paymentMode: paymentMode,
          referenceNumber: referenceNumber,
          notes: notes,
          status: status,
        );
    await refresh();
    ref.invalidate(paymentSummaryNotifierProvider);
  }

  Future<void> updateStatus(Payment payment, PaymentStatus status) async {
    final updated = await ref.read(paymentRepositoryProvider).updateStatus(payment.id, status);

    state = state.whenData(
      (payments) => [for (final existing in payments) existing.id == updated.id ? updated : existing],
    );
    ref.invalidate(paymentSummaryNotifierProvider);
  }
}
