enum PaymentType {
  setupFee('setup_fee', 'Setup Fee'),
  annualMaintenance('annual_maintenance', 'Annual Maintenance'),
  additionalService('additional_service', 'Additional Service'),
  other('other', 'Other');

  const PaymentType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PaymentType fromApiValue(String value) => PaymentType.values.firstWhere((t) => t.apiValue == value);
}

enum PaymentMode {
  cash('cash', 'Cash'),
  bankTransfer('bank_transfer', 'Bank Transfer'),
  upi('upi', 'UPI'),
  cheque('cheque', 'Cheque'),
  online('online', 'Online Transfer');

  const PaymentMode(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PaymentMode fromApiValue(String value) => PaymentMode.values.firstWhere((m) => m.apiValue == value);
}

enum PaymentStatus {
  pending('pending', 'Pending'),
  paid('paid', 'Paid'),
  partial('partial', 'Partially Paid'),
  cancelled('cancelled', 'Cancelled');

  const PaymentStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PaymentStatus fromApiValue(String value) => PaymentStatus.values.firstWhere((s) => s.apiValue == value);
}

class Payment {
  const Payment({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.paymentType,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.currencyCode,
    required this.paymentDate,
    required this.paymentMode,
    required this.referenceNumber,
    required this.notes,
    required this.status,
    required this.createdByName,
    this.receiptSentAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      paymentType: PaymentType.fromApiValue(json['payment_type'] as String),
      amount: double.parse(json['amount'] as String),
      paidAmount: double.parse(json['paid_amount'] as String? ?? '0'),
      remainingAmount: double.parse(json['remaining_amount'] as String? ?? '0'),
      currencyCode: json['currency_code'] as String,
      paymentDate: DateTime.parse(json['payment_date'] as String),
      paymentMode: PaymentMode.fromApiValue(json['payment_mode'] as String),
      referenceNumber: json['reference_number'] as String?,
      notes: json['notes'] as String?,
      status: PaymentStatus.fromApiValue(json['status'] as String),
      createdByName: json['created_by_name'] as String?,
      receiptSentAt: json['receipt_sent_at'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final PaymentType paymentType;

  /// How much of [amount] has actually arrived, and how much is still owed.
  /// The balance is computed by the API from those two, never stored, so it
  /// cannot drift out of step with them.
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String currencyCode;
  final DateTime paymentDate;
  final PaymentMode paymentMode;
  final String? referenceNumber;
  final String? notes;
  final PaymentStatus status;
  final String? createdByName;

  /// When the receipt was last emailed to the school's admins, if ever.
  final String? receiptSentAt;

  /// True while money is still owed - the case the UI has to spell out
  /// rather than leaving someone to subtract two figures.
  bool get hasBalance => remainingAmount > 0 && status != PaymentStatus.cancelled;

  Payment copyWith({PaymentStatus? status}) {
    return Payment(
      id: id,
      schoolId: schoolId,
      schoolName: schoolName,
      paymentType: paymentType,
      amount: amount,
      paidAmount: paidAmount,
      remainingAmount: remainingAmount,
      currencyCode: currencyCode,
      paymentDate: paymentDate,
      paymentMode: paymentMode,
      referenceNumber: referenceNumber,
      notes: notes,
      status: status ?? this.status,
      createdByName: createdByName,
      receiptSentAt: receiptSentAt,
    );
  }
}

/// Total (or monthly, or pending) collection for one currency - the
/// backend never blends currencies into one figure (CLAUDE.md rule 5).
class CurrencyTotal {
  const CurrencyTotal({required this.currencyCode, required this.total});

  factory CurrencyTotal.fromJson(Map<String, dynamic> json) {
    return CurrencyTotal(currencyCode: json['currency_code'] as String, total: double.parse(json['total'] as String));
  }

  final String currencyCode;
  final double total;
}

class PaymentSummary {
  const PaymentSummary({
    required this.totalByCurrency,
    required this.monthlyByCurrency,
    required this.pendingByCurrency,
    required this.pendingCount,
  });

  factory PaymentSummary.fromJson(Map<String, dynamic> json) {
    List<CurrencyTotal> parse(String key) =>
        (json[key] as List).cast<Map<String, dynamic>>().map(CurrencyTotal.fromJson).toList();

    return PaymentSummary(
      totalByCurrency: parse('total_by_currency'),
      monthlyByCurrency: parse('monthly_by_currency'),
      pendingByCurrency: parse('pending_by_currency'),
      pendingCount: json['pending_count'] as int,
    );
  }

  final List<CurrencyTotal> totalByCurrency;
  final List<CurrencyTotal> monthlyByCurrency;
  final List<CurrencyTotal> pendingByCurrency;
  final int pendingCount;
}
