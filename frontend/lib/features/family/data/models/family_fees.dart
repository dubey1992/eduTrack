/// A child's fees as the Family app shows them (docs/parent-student-app.md,
/// F3): the year's instalments, its receipts, any credit, and how to pay.
/// Read only - the app takes no payments.
library;

/// Where one instalment stands, in a parent's words.
enum InstalmentStatus {
  paid('paid', 'Paid'),
  partPaid('part_paid', 'Part paid'),
  due('due', 'Due'),
  overdue('overdue', 'Overdue'),
  waived('waived', 'Waived');

  const InstalmentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static InstalmentStatus fromWire(String value) =>
      values.firstWhere((status) => status.wire == value, orElse: () => due);
}

class FamilyFees {
  const FamilyFees({
    required this.yearName,
    required this.currencyCode,
    required this.totals,
    required this.instalments,
    required this.receipts,
    required this.credit,
    required this.howToPay,
    this.payeeName,
    this.paymentNote,
  });

  factory FamilyFees.fromJson(Map<String, dynamic> json) {
    final year = json['academic_year'] as Map<String, dynamic>?;
    final totals = json['totals'] as Map<String, dynamic>?;

    return FamilyFees(
      yearName: year?['name'] as String?,
      currencyCode: json['currency_code'] as String,
      totals: totals == null ? null : FeeTotals.fromJson(totals),
      instalments: [
        for (final line in json['installments'] as List<dynamic>) Instalment.fromJson(line as Map<String, dynamic>),
      ],
      receipts: [
        for (final line in json['receipts'] as List<dynamic>) FamilyReceipt.fromJson(line as Map<String, dynamic>),
      ],
      credit: double.parse(json['credit'] as String),
      howToPay: HowToPay.fromJson(json['how_to_pay'] as Map<String, dynamic>),
      payeeName: json['payee_name'] as String?,
      paymentNote: json['payment_note'] as String?,
    );
  }

  /// The year the fees are for; null when the child has none yet.
  final String? yearName;
  final String currencyCode;
  final FeeTotals? totals;
  final List<Instalment> instalments;
  final List<FamilyReceipt> receipts;

  /// Money the school holds for the child, paid towards later instalments.
  final double credit;
  final HowToPay howToPay;

  /// For "Pay with any UPI app" (docs/mobile-apps-review.md, 6.4): whom the
  /// money goes to, and the note that tells the office whose fees it is.
  final String? payeeName;
  final String? paymentNote;

  /// What the school has let off: the instalments it waived, after any
  /// discount and anything paid on them before.
  double get waived => instalments
      .where((line) => line.status == InstalmentStatus.waived)
      .fold(0, (sum, line) => sum + (line.amount - line.discount - line.paid));

  /// What to pay now: everything overdue, or else the next instalment still
  /// owing. Null when nothing is owed.
  double? get amountToPayNow {
    final overdue = totals?.overdue ?? 0;
    if (overdue > 0) return overdue;

    final owing = instalments.where((line) => line.balance > 0).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return owing.isEmpty ? null : owing.first.balance;
  }

  /// A upi://pay link for the phone's UPI apps; null where UPI cannot be
  /// used - no UPI ID, a school outside India's rupee, or nothing owed.
  Uri? get upiPayLink {
    final upiId = howToPay.upiId;
    final amount = amountToPayNow;
    if (upiId == null || currencyCode != 'INR' || amount == null) return null;

    // Spaces as %20, not the + a query map would give: not every UPI app
    // reads + as a space. The UPI ID is left as the school wrote it.
    final parts = [
      'pa=$upiId',
      if (payeeName != null) 'pn=${Uri.encodeComponent(payeeName!)}',
      'am=${amount.toStringAsFixed(2)}',
      'cu=INR',
      if (paymentNote != null) 'tn=${Uri.encodeComponent(paymentNote!)}',
    ];
    return Uri.parse('upi://pay?${parts.join('&')}');
  }
}

class FeeTotals {
  const FeeTotals({
    required this.charged,
    required this.discount,
    required this.paid,
    required this.balance,
    required this.overdue,
  });

  factory FeeTotals.fromJson(Map<String, dynamic> json) => FeeTotals(
    charged: double.parse(json['charged'] as String),
    discount: double.parse(json['discount'] as String),
    paid: double.parse(json['paid'] as String),
    balance: double.parse(json['balance'] as String),
    overdue: double.parse(json['overdue'] as String),
  );

  final double charged;
  final double discount;
  final double paid;
  final double balance;
  final double overdue;
}

class Instalment {
  const Instalment({
    required this.id,
    required this.label,
    required this.dueDate,
    required this.amount,
    required this.discount,
    required this.paid,
    required this.balance,
    required this.status,
  });

  factory Instalment.fromJson(Map<String, dynamic> json) => Instalment(
    id: json['id'] as int,
    label: json['label'] as String,
    dueDate: DateTime.parse(json['due_date'] as String),
    amount: double.parse(json['amount'] as String),
    discount: double.parse(json['discount'] as String),
    paid: double.parse(json['paid'] as String),
    balance: double.parse(json['balance'] as String),
    status: InstalmentStatus.fromWire(json['status'] as String),
  );

  final int id;
  final String label;
  final DateTime dueDate;
  final double amount;
  final double discount;
  final double paid;
  final double balance;
  final InstalmentStatus status;
}

class FamilyReceipt {
  const FamilyReceipt({
    required this.id,
    required this.number,
    required this.date,
    required this.amount,
    required this.currencyCode,
    required this.paymentMode,
    required this.cancelled,
  });

  factory FamilyReceipt.fromJson(Map<String, dynamic> json) => FamilyReceipt(
    id: json['id'] as int,
    number: json['number'] as String,
    date: DateTime.parse(json['date'] as String),
    amount: double.parse(json['amount'] as String),
    currencyCode: json['currency_code'] as String,
    paymentMode: json['payment_mode'] as String,
    cancelled: json['cancelled'] as bool,
  );

  final int id;
  final String number;
  final DateTime date;
  final double amount;
  final String currencyCode;

  /// As the server writes it: cash, upi, bank_transfer, cheque, card, online_transfer.
  final String paymentMode;
  final bool cancelled;

  /// How it was paid, in words.
  String get paymentModeLabel => switch (paymentMode) {
    'cash' => 'Cash',
    'upi' => 'UPI',
    'bank_transfer' => 'Bank transfer',
    'cheque' => 'Cheque',
    'card' => 'Card',
    'online_transfer' => 'Online transfer',
    _ => paymentMode,
  };
}

/// How to pay at this school, in its own words; each part is null when the
/// school left it empty.
class HowToPay {
  const HowToPay({this.counterHours, this.bankDetails, this.upiId, this.officePhone});

  factory HowToPay.fromJson(Map<String, dynamic> json) => HowToPay(
    counterHours: json['counter_hours'] as String?,
    bankDetails: json['bank_details'] as String?,
    upiId: json['upi_id'] as String?,
    officePhone: json['office_phone'] as String?,
  );

  final String? counterHours;
  final String? bankDetails;
  final String? upiId;
  final String? officePhone;

  bool get isEmpty => counterHours == null && bankDetails == null && upiId == null && officePhone == null;
}
