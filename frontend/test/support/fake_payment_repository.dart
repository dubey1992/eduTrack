import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';

import 'fake_pagination.dart';

/// The same rules the API applies, so a fake can never hand a test a payment
/// the real system could not have produced: the status follows the money,
/// and what remains is derived from it.
PaymentStatus resolveStatus(double amount, double paid, PaymentStatus? requested) {
  if (requested == PaymentStatus.cancelled) return PaymentStatus.cancelled;
  if (paid <= 0) return PaymentStatus.pending;
  if (paid >= amount) return PaymentStatus.paid;

  return PaymentStatus.partial;
}

double resolvePaidAmount({
  required double amount,
  required double? paidAmount,
  required PaymentStatus? status,
  double fallback = 0,
}) {
  if (paidAmount != null) return paidAmount > amount ? amount : paidAmount;

  return switch (status) {
    PaymentStatus.paid => amount,
    PaymentStatus.pending || PaymentStatus.cancelled => 0,
    _ => fallback > amount ? amount : fallback,
  };
}

double resolveRemaining(double amount, double paid, PaymentStatus? status) {
  if (status == PaymentStatus.cancelled) return 0;
  final remaining = amount - paid;

  return remaining < 0 ? 0 : remaining;
}

class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({
    List<Payment>? payments,
    PaymentSummary? summary,
    this.failCreateWith,
    this.failUpdateWith,
    this.failListPageWith,
    this.failSendReceiptWith,
  }) : _payments = payments ?? [],
       _summary =
           summary ??
           const PaymentSummary(totalByCurrency: [], monthlyByCurrency: [], pendingByCurrency: [], pendingCount: 0);

  final List<Payment> _payments;
  final PaymentSummary _summary;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failListPageWith;
  Failure? failSendReceiptWith;
  int sendReceiptCalls = 0;

  List<Payment> _filtered({int? schoolId}) {
    return schoolId == null ? _payments : _payments.where((p) => p.schoolId == schoolId).toList();
  }

  @override
  Future<List<Payment>> list({int? schoolId}) async {
    return List.unmodifiable(_filtered(schoolId: schoolId));
  }

  @override
  Future<PaginatedResponse<Payment>> listPage({int? schoolId, required int page, required int perPage}) async {
    if (failListPageWith != null) throw failListPageWith!;
    return paginateFake(
      _filtered(schoolId: schoolId),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<Payment> create({
    required int schoolId,
    required PaymentType paymentType,
    required double amount,
    double? paidAmount,
    required DateTime paymentDate,
    required PaymentMode paymentMode,
    String? referenceNumber,
    String? notes,
    required PaymentStatus status,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final paid = resolvePaidAmount(amount: amount, paidAmount: paidAmount, status: status);

    final payment = Payment(
      id: _payments.length + 1,
      schoolId: schoolId,
      schoolName: 'Test School',
      paymentType: paymentType,
      amount: amount,
      paidAmount: paid,
      remainingAmount: resolveRemaining(amount, paid, status),
      currencyCode: 'INR',
      paymentDate: paymentDate,
      paymentMode: paymentMode,
      referenceNumber: referenceNumber,
      notes: notes,
      status: resolveStatus(amount, paid, status),
      createdByName: 'Test User',
    );
    _payments.add(payment);
    return payment;
  }

  @override
  Future<Payment> sendReceipt(int paymentId) async {
    if (failSendReceiptWith != null) throw failSendReceiptWith!;

    sendReceiptCalls++;
    final index = _payments.indexWhere((p) => p.id == paymentId);
    _payments[index] = _payments[index].copyWith();

    return _payments[index];
  }

  @override
  Future<Payment> updateStatus(int paymentId, PaymentStatus status) async {
    final index = _payments.indexWhere((p) => p.id == paymentId);
    final updated = _payments[index].copyWith(status: status);
    _payments[index] = updated;
    return updated;
  }

  @override
  Future<Payment> update(
    int paymentId, {
    PaymentType? paymentType,
    double? amount,
    double? paidAmount,
    DateTime? paymentDate,
    PaymentMode? paymentMode,
    String? referenceNumber,
    String? notes,
    PaymentStatus? status,
  }) async {
    if (failUpdateWith != null) throw failUpdateWith!;
    final index = _payments.indexWhere((p) => p.id == paymentId);
    final existing = _payments[index];
    final newAmount = amount ?? existing.amount;
    final paid = resolvePaidAmount(
      amount: newAmount,
      paidAmount: paidAmount,
      status: status ?? existing.status,
      fallback: existing.paidAmount,
    );
    final updated = Payment(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      paymentType: paymentType ?? existing.paymentType,
      amount: newAmount,
      paidAmount: paid,
      remainingAmount: resolveRemaining(newAmount, paid, status ?? existing.status),
      currencyCode: existing.currencyCode,
      paymentDate: paymentDate ?? existing.paymentDate,
      paymentMode: paymentMode ?? existing.paymentMode,
      referenceNumber: referenceNumber,
      notes: notes,
      status: resolveStatus(newAmount, paid, status ?? existing.status),
      createdByName: existing.createdByName,
    );
    _payments[index] = updated;
    return updated;
  }

  @override
  Future<PaymentSummary> summary() async => _summary;
}
