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
  partial('partial', 'Partial'),
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
    required this.currencyCode,
    required this.paymentDate,
    required this.paymentMode,
    required this.referenceNumber,
    required this.notes,
    required this.status,
    required this.createdByName,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      paymentType: PaymentType.fromApiValue(json['payment_type'] as String),
      amount: double.parse(json['amount'] as String),
      currencyCode: json['currency_code'] as String,
      paymentDate: DateTime.parse(json['payment_date'] as String),
      paymentMode: PaymentMode.fromApiValue(json['payment_mode'] as String),
      referenceNumber: json['reference_number'] as String?,
      notes: json['notes'] as String?,
      status: PaymentStatus.fromApiValue(json['status'] as String),
      createdByName: json['created_by_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final PaymentType paymentType;
  final double amount;
  final String currencyCode;
  final DateTime paymentDate;
  final PaymentMode paymentMode;
  final String? referenceNumber;
  final String? notes;
  final PaymentStatus status;
  final String? createdByName;

  Payment copyWith({PaymentStatus? status}) {
    return Payment(
      id: id,
      schoolId: schoolId,
      schoolName: schoolName,
      paymentType: paymentType,
      amount: amount,
      currencyCode: currencyCode,
      paymentDate: paymentDate,
      paymentMode: paymentMode,
      referenceNumber: referenceNumber,
      notes: notes,
      status: status ?? this.status,
      createdByName: createdByName,
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
