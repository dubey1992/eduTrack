import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/payment.dart';
import '../data/payment_repository.dart';
import 'payment_summary_notifier.dart';

final paymentListNotifierProvider = AsyncNotifierProvider<PaymentListNotifier, PagedList<Payment>>(
  PaymentListNotifier.new,
);

class PaymentListNotifier extends AsyncNotifier<PagedList<Payment>> {
  /// Set via [setSchoolFilter] - Payments is already a SUPER_ADMIN-only
  /// feature, so this is the only filter dimension that needs one.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Payment>> build() => _fetch();

  Future<PagedList<Payment>> _fetch() async {
    final response = await ref
        .read(paymentRepositoryProvider)
        .listPage(schoolId: _schoolId, page: _page, perPage: _perPage);

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
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
    _page = 1;
    await refresh();
    ref.invalidate(paymentSummaryNotifierProvider);
  }

  Future<void> updatePayment(
    Payment payment, {
    PaymentType? paymentType,
    double? amount,
    DateTime? paymentDate,
    PaymentMode? paymentMode,
    String? referenceNumber,
    String? notes,
    PaymentStatus? status,
  }) async {
    final updated = await ref
        .read(paymentRepositoryProvider)
        .update(
          payment.id,
          paymentType: paymentType,
          amount: amount,
          paymentDate: paymentDate,
          paymentMode: paymentMode,
          referenceNumber: referenceNumber,
          notes: notes,
          status: status,
        );

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(paymentSummaryNotifierProvider);
  }

  Future<void> updateStatus(Payment payment, PaymentStatus status) async {
    final updated = await ref.read(paymentRepositoryProvider).updateStatus(payment.id, status);

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(paymentSummaryNotifierProvider);
  }
}
