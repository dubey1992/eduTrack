/// Where a fee payment taken offline stands (docs/offline-web.md, O4).
enum OfflineFeeStatus {
  receipted('receipted', 'Receipted'),
  toSettle('to_settle', 'To settle'),
  credited('credited', 'Kept on account'),
  refunded('refunded', 'Handed back');

  const OfflineFeeStatus(this.wire, this.label);

  final String wire;
  final String label;

  static OfflineFeeStatus fromWire(String value) =>
      values.firstWhere((status) => status.wire == value, orElse: () => toSettle);
}

/// A payment the counter took while the internet was down, as the server
/// recorded it when it arrived.
class OfflineFeePayment {
  const OfflineFeePayment({
    required this.id,
    required this.provisionalNumber,
    required this.status,
    required this.studentName,
    required this.admissionNumber,
    required this.receiptDate,
    required this.amount,
    required this.currencyCode,
    required this.paymentMode,
    this.problem,
    this.reference,
    this.takenBy,
    this.receiptNumber,
    this.settledBy,
    this.settleNote,
    this.refundMode,
  });

  factory OfflineFeePayment.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>;
    final receipt = json['receipt'] as Map<String, dynamic>?;
    return OfflineFeePayment(
      id: json['id'] as int,
      provisionalNumber: json['provisional_number'] as String,
      status: OfflineFeeStatus.fromWire(json['status'] as String),
      studentName: student['name'] as String,
      admissionNumber: student['admission_number'] as String,
      receiptDate: json['receipt_date'] as String,
      amount: double.parse(json['amount'] as String),
      currencyCode: json['currency_code'] as String,
      paymentMode: json['payment_mode'] as String,
      problem: json['problem'] as String?,
      reference: json['reference'] as String?,
      takenBy: json['taken_by'] as String?,
      receiptNumber: receipt?['receipt_number'] as String?,
      settledBy: json['settled_by'] as String?,
      settleNote: json['settle_note'] as String?,
      refundMode: json['refund_mode'] as String?,
    );
  }

  final int id;
  final String provisionalNumber;
  final OfflineFeeStatus status;
  final String studentName;
  final String admissionNumber;

  /// yyyy-MM-dd: the day the money was taken.
  final String receiptDate;
  final double amount;
  final String currencyCode;
  final String paymentMode;

  /// Why it could not become a receipt when it arrived.
  final String? problem;
  final String? reference;
  final String? takenBy;
  final String? receiptNumber;
  final String? settledBy;
  final String? settleNote;
  final String? refundMode;
}
