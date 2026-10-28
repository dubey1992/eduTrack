/// Money received for a student's fees, and the receipt it was given
/// (docs/fees.md, F3).
library;

enum PaymentMode {
  cash('cash', 'Cash'),
  bankTransfer('bank_transfer', 'Bank Transfer'),
  upi('upi', 'UPI'),
  cheque('cheque', 'Cheque'),
  card('card', 'Card'),
  onlineTransfer('online_transfer', 'Online Transfer');

  const PaymentMode(this.wire, this.label);

  final String wire;
  final String label;

  /// A cheque is the one payment that cannot be traced without its number.
  bool get needsReference => this == cheque;

  static PaymentMode fromWire(String value) => values.firstWhere((mode) => mode.wire == value, orElse: () => cash);
}

/// How much of a receipt went to one installment.
class ReceiptAllocation {
  const ReceiptAllocation({required this.dueId, required this.label, required this.dueDate, required this.amount});

  factory ReceiptAllocation.fromJson(Map<String, dynamic> json) => ReceiptAllocation(
    dueId: json['due_id'] as int,
    label: json['label'] as String,
    dueDate: DateTime.parse(json['due_date'] as String),
    amount: json['amount'].toString(),
  );

  final int dueId;
  final String label;
  final DateTime dueDate;
  final String amount;
}

class FeeReceipt {
  const FeeReceipt({
    required this.id,
    required this.receiptNumber,
    required this.receiptDate,
    required this.amount,
    required this.currencyCode,
    required this.paymentMode,
    required this.isCancelled,
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.allocations,
    required this.studentBalance,
    this.creditAmount = '0.00',
    this.balanceBefore,
    this.balanceAfter,
    this.className,
    this.sectionName,
    this.reference,
    this.note,
    this.receivedByName,
    this.cancelReason,
    this.cancelledAt,
    this.emailedAt,
  });

  factory FeeReceipt.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>;
    DateTime? instant(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

    return FeeReceipt(
      id: json['id'] as int,
      receiptNumber: json['receipt_number'] as String,
      receiptDate: DateTime.parse(json['receipt_date'] as String),
      amount: json['amount'].toString(),
      currencyCode: json['currency_code'] as String,
      paymentMode: PaymentMode.fromWire(json['payment_mode'] as String),
      isCancelled: json['status'] == 'cancelled',
      studentId: student['id'] as int,
      studentName: student['name'] as String,
      admissionNumber: student['admission_number'] as String,
      className: student['class_name'] as String?,
      sectionName: student['section_name'] as String?,
      reference: json['reference'] as String?,
      note: json['note'] as String?,
      receivedByName: (json['received_by'] as Map<String, dynamic>?)?['name'] as String?,
      allocations: [
        for (final row in json['allocations'] as List? ?? const [])
          ReceiptAllocation.fromJson(row as Map<String, dynamic>),
      ],
      studentBalance: json['student_balance']?.toString() ?? '0.00',
      creditAmount: json['credit_amount']?.toString() ?? '0.00',
      balanceBefore: json['balance_before']?.toString(),
      balanceAfter: json['balance_after']?.toString(),
      cancelReason: json['cancel_reason'] as String?,
      cancelledAt: instant(json['cancelled_at']),
      emailedAt: instant(json['emailed_at']),
    );
  }

  final int id;
  final String receiptNumber;

  /// The day the money was received, in the school's calendar.
  final DateTime receiptDate;
  final String amount;
  final String currencyCode;
  final PaymentMode paymentMode;

  /// A cancelled receipt stays on record with its number; the installments
  /// it paid are owed again.
  final bool isCancelled;
  final int studentId;
  final String studentName;
  final String admissionNumber;
  final String? className;
  final String? sectionName;
  final String? reference;
  final String? note;
  final String? receivedByName;
  final List<ReceiptAllocation> allocations;

  /// What the student still owes now, across every year.
  final String studentBalance;

  /// What the student owed just before this payment, and just after it -
  /// as at the receipt, so a reprint months later shows the same figures.
  /// The part held as the student's credit (F6): the allocations add up to
  /// the amount less this.
  final String creditAmount;
  final String? balanceBefore;
  final String? balanceAfter;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final DateTime? emailedAt;
}

/// A receipt as a student's statement lists it.
class ReceiptSummary {
  const ReceiptSummary({
    required this.id,
    required this.receiptNumber,
    required this.receiptDate,
    required this.amount,
    required this.paymentModeLabel,
    required this.isCancelled,
  });

  factory ReceiptSummary.fromJson(Map<String, dynamic> json) => ReceiptSummary(
    id: json['id'] as int,
    receiptNumber: json['receipt_number'] as String,
    receiptDate: DateTime.parse(json['receipt_date'] as String),
    amount: json['amount'].toString(),
    paymentModeLabel: json['payment_mode_label'] as String? ?? '',
    isCancelled: json['status'] == 'cancelled',
  );

  final int id;
  final String receiptNumber;
  final DateTime receiptDate;
  final String amount;
  final String paymentModeLabel;
  final bool isCancelled;
}

/// One installment paid by a specific amount, when the office chooses
/// rather than letting the payment go to the oldest first.
typedef PaymentAllocation = ({int dueId, String amount});
