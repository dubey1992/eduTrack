import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/payment.dart';
import '../data/payment_repository.dart';

final paymentSummaryNotifierProvider = AsyncNotifierProvider<PaymentSummaryNotifier, PaymentSummary>(
  PaymentSummaryNotifier.new,
);

class PaymentSummaryNotifier extends AsyncNotifier<PaymentSummary> {
  @override
  Future<PaymentSummary> build() {
    return ref.read(paymentRepositoryProvider).summary();
  }
}
