/// A student's fee credit (docs/fees.md, F6): money paid that nothing is owed
/// against yet. It pays the student's next fees on its own, and the office
/// can refund it.
library;

/// What a student holds in one currency.
class FeeCreditBalance {
  const FeeCreditBalance({required this.currencyCode, required this.balance});

  factory FeeCreditBalance.fromJson(Map<String, dynamic> json) =>
      FeeCreditBalance(currencyCode: json['currency_code'] as String, balance: json['balance'].toString());

  final String currencyCode;

  /// A money string, as the server wrote it.
  final String balance;
}

/// One movement of the credit. The amount is signed: what came in is
/// positive, what went out (paid a fee, refunded) negative.
class FeeCreditEntry {
  const FeeCreditEntry({
    required this.id,
    required this.kind,
    required this.kindLabel,
    required this.amount,
    required this.currencyCode,
    required this.entryDate,
    this.dueLabel,
    this.receiptNumber,
    this.paymentModeLabel,
    this.reference,
    this.note,
    this.createdByName,
  });

  factory FeeCreditEntry.fromJson(Map<String, dynamic> json) => FeeCreditEntry(
    id: json['id'] as int,
    kind: json['kind'] as String,
    kindLabel: json['kind_label'] as String,
    amount: json['amount'].toString(),
    currencyCode: json['currency_code'] as String,
    entryDate: DateTime.parse(json['entry_date'] as String),
    dueLabel: (json['due'] as Map<String, dynamic>?)?['label'] as String?,
    receiptNumber: (json['receipt'] as Map<String, dynamic>?)?['receipt_number'] as String?,
    paymentModeLabel: json['payment_mode_label'] as String?,
    reference: json['reference'] as String?,
    note: json['note'] as String?,
    createdByName: (json['created_by'] as Map<String, dynamic>?)?['name'] as String?,
  );

  final int id;

  /// released, overpaid, returned, applied, refunded or reversed.
  final String kind;
  final String kindLabel;
  final String amount;
  final String currencyCode;

  /// A date in the school's calendar - never converted.
  final DateTime entryDate;

  /// The installment it came from or paid.
  final String? dueLabel;

  /// The receipt it came from, or was taken back for.
  final String? receiptNumber;

  /// A refund's how, reference and reason.
  final String? paymentModeLabel;
  final String? reference;
  final String? note;
  final String? createdByName;

  bool get isIn => !amount.startsWith('-');

  /// The amount without its sign, for showing beside an in/out arrow.
  String get size => isIn ? amount : amount.substring(1);
}
