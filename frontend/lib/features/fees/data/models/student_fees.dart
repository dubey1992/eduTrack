/// What students owe (docs/fees.md, F2): each line on a student's account,
/// and the totals the office reads.
library;

import 'fee_receipt.dart';

enum FeeDueStatus {
  pending('pending', 'Due'),
  partial('partial', 'Part paid'),
  paid('paid', 'Paid'),
  waived('waived', 'Waived'),
  cancelled('cancelled', 'Cancelled');

  const FeeDueStatus(this.wire, this.label);

  final String wire;
  final String label;

  static FeeDueStatus fromWire(String value) =>
      values.firstWhere((status) => status.wire == value, orElse: () => pending);
}

/// One installment of one fee, charged to one student. Amounts stay the
/// strings the server wrote: money is not a double.
class FeeDue {
  const FeeDue({
    required this.id,
    required this.feeHeadName,
    required this.label,
    required this.dueDate,
    required this.amount,
    required this.discountAmount,
    required this.paidAmount,
    required this.balance,
    required this.status,
    required this.isOverdue,
    this.cancelledReason,
  });

  factory FeeDue.fromJson(Map<String, dynamic> json) {
    return FeeDue(
      id: json['id'] as int,
      feeHeadName: (json['fee_head'] as Map<String, dynamic>)['name'] as String,
      label: json['label'] as String,
      dueDate: DateTime.parse(json['due_date'] as String),
      amount: json['amount'].toString(),
      discountAmount: json['discount_amount'].toString(),
      paidAmount: json['paid_amount'].toString(),
      balance: json['balance'].toString(),
      status: FeeDueStatus.fromWire(json['status'] as String),
      isOverdue: json['is_overdue'] as bool? ?? false,
      cancelledReason: json['cancelled_reason'] as String?,
    );
  }

  final int id;
  final String feeHeadName;
  final String label;

  /// A date in the school's calendar - never converted.
  final DateTime dueDate;
  final String amount;
  final String discountAmount;
  final String paidAmount;
  final String balance;
  final FeeDueStatus status;
  final bool isOverdue;

  /// Why the school stopped charging it: class_changed, route_changed, left
  /// or fee_changed.
  final String? cancelledReason;

  bool get isCancelled => status == FeeDueStatus.cancelled;
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
    charged: json['charged'].toString(),
    discount: json['discount'].toString(),
    paid: json['paid'].toString(),
    balance: json['balance'].toString(),
    overdue: json['overdue'].toString(),
  );

  final String charged;
  final String discount;
  final String paid;
  final String balance;
  final String overdue;
}

/// Who the student is, as a fee statement names them.
class FeeStudent {
  const FeeStudent({
    required this.id,
    required this.name,
    required this.admissionNumber,
    required this.status,
    this.className,
    this.sectionName,
    this.admissionDate,
  });

  factory FeeStudent.fromJson(Map<String, dynamic> json) => FeeStudent(
    id: json['id'] as int,
    name: json['name'] as String,
    admissionNumber: json['admission_number'] as String,
    status: json['status'] as String? ?? 'active',
    className: json['class_name'] as String?,
    sectionName: json['section_name'] as String?,
    admissionDate: json['admission_date'] is String ? DateTime.tryParse(json['admission_date'] as String) : null,
  );

  final int id;
  final String name;
  final String admissionNumber;
  final String status;
  final String? className;
  final String? sectionName;
  final DateTime? admissionDate;

  /// "Class 8 - A", or whichever half is known.
  String get classLabel => [?className, ?sectionName].join(' - ');
}

/// One student's account for one academic year.
class StudentFeeStatement {
  const StudentFeeStatement({
    required this.student,
    required this.academicYearId,
    required this.academicYearName,
    required this.currencyCode,
    required this.dues,
    required this.totals,
    this.receipts = const [],
  });

  factory StudentFeeStatement.fromJson(Map<String, dynamic> json) {
    final year = json['academic_year'] as Map<String, dynamic>;

    return StudentFeeStatement(
      student: FeeStudent.fromJson(json['student'] as Map<String, dynamic>),
      academicYearId: year['id'] as int,
      academicYearName: year['name'] as String,
      currencyCode: json['currency_code'] as String,
      dues: [for (final row in json['dues'] as List? ?? const []) FeeDue.fromJson(row as Map<String, dynamic>)],
      totals: FeeTotals.fromJson(json['totals'] as Map<String, dynamic>),
      receipts: [
        for (final row in json['receipts'] as List? ?? const []) ReceiptSummary.fromJson(row as Map<String, dynamic>),
      ],
    );
  }

  final FeeStudent student;
  final int academicYearId;
  final String academicYearName;
  final String currencyCode;
  final List<FeeDue> dues;
  final FeeTotals totals;

  /// What was paid against this year, newest first (F3).
  final List<ReceiptSummary> receipts;

  /// The installments a payment can go to, oldest first.
  List<FeeDue> get payable => [
    for (final due in dues)
      if (due.status == FeeDueStatus.pending || due.status == FeeDueStatus.partial) due,
  ];
}

/// One line of the Student Fees list.
class StudentBalance {
  const StudentBalance({
    required this.student,
    required this.charged,
    required this.paid,
    required this.balance,
    required this.overdue,
    required this.currencyCode,
    this.nextDueDate,
  });

  factory StudentBalance.fromJson(Map<String, dynamic> json) => StudentBalance(
    student: FeeStudent.fromJson(json['student'] as Map<String, dynamic>),
    charged: json['charged'].toString(),
    paid: json['paid'].toString(),
    balance: json['balance'].toString(),
    overdue: json['overdue'].toString(),
    currencyCode: json['currency_code'] as String,
    nextDueDate: json['next_due_date'] is String ? DateTime.tryParse(json['next_due_date'] as String) : null,
  );

  final FeeStudent student;
  final String charged;
  final String paid;
  final String balance;
  final String overdue;
  final String currencyCode;
  final DateTime? nextDueDate;
}
