import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';

class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({List<Payment>? payments, PaymentSummary? summary, this.failCreateWith})
    : _payments = payments ?? [],
      _summary =
          summary ??
          const PaymentSummary(
            totalByCurrency: [],
            monthlyByCurrency: [],
            pendingByCurrency: [],
            pendingCount: 0,
          );

  final List<Payment> _payments;
  final PaymentSummary _summary;
  Failure? failCreateWith;

  @override
  Future<List<Payment>> list({int? schoolId}) async {
    if (schoolId == null) return List.unmodifiable(_payments);
    return _payments.where((p) => p.schoolId == schoolId).toList();
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
  Future<PaymentSummary> summary() async => _summary;
}
