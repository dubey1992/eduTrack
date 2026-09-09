import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';

import 'fake_pagination.dart';

class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({
    List<Payment>? payments,
    PaymentSummary? summary,
    this.failCreateWith,
    this.failUpdateWith,
    this.failListPageWith,
  }) : _payments = payments ?? [],
       _summary =
           summary ??
           const PaymentSummary(totalByCurrency: [], monthlyByCurrency: [], pendingByCurrency: [], pendingCount: 0);

  final List<Payment> _payments;
  final PaymentSummary _summary;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failListPageWith;

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
    required DateTime paymentDate,
    required PaymentMode paymentMode,
    String? referenceNumber,
    String? notes,
    required PaymentStatus status,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final payment = Payment(
      id: _payments.length + 1,
      schoolId: schoolId,
      schoolName: 'Test School',
      paymentType: paymentType,
      amount: amount,
      currencyCode: 'INR',
      paymentDate: paymentDate,
      paymentMode: paymentMode,
      referenceNumber: referenceNumber,
      notes: notes,
      status: status,
      createdByName: 'Test User',
    );
    _payments.add(payment);
    return payment;
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
    DateTime? paymentDate,
    PaymentMode? paymentMode,
    String? referenceNumber,
    String? notes,
    PaymentStatus? status,
  }) async {
    if (failUpdateWith != null) throw failUpdateWith!;
    final index = _payments.indexWhere((p) => p.id == paymentId);
    final existing = _payments[index];
    final updated = Payment(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      paymentType: paymentType ?? existing.paymentType,
      amount: amount ?? existing.amount,
      currencyCode: existing.currencyCode,
      paymentDate: paymentDate ?? existing.paymentDate,
      paymentMode: paymentMode ?? existing.paymentMode,
      referenceNumber: referenceNumber,
      notes: notes,
      status: status ?? existing.status,
      createdByName: existing.createdByName,
    );
    _payments[index] = updated;
    return updated;
  }

  @override
  Future<PaymentSummary> summary() async => _summary;
}
