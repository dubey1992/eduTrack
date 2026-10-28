/// What students owe (docs/fees.md, F2): each line on a student's account,
/// and the totals the office reads.
library;

import '../money_text.dart';
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
    this.feeHeadId,
    required this.label,
    required this.dueDate,
    required this.amount,
    required this.discountAmount,
    required this.paidAmount,
    required this.balance,
    required this.status,
    required this.isOverdue,
    this.cancelledReason,
    this.isLateFine = false,
    this.fineForDueId,
    this.waiveReason,
    this.waivedAt,
  });

  factory FeeDue.fromJson(Map<String, dynamic> json) {
    return FeeDue(
      id: json['id'] as int,
      feeHeadName: (json['fee_head'] as Map<String, dynamic>)['name'] as String,
      feeHeadId: (json['fee_head'] as Map<String, dynamic>)['id'] as int?,
      label: json['label'] as String,
      dueDate: DateTime.parse(json['due_date'] as String),
      amount: json['amount'].toString(),
      discountAmount: json['discount_amount'].toString(),
      paidAmount: json['paid_amount'].toString(),
      balance: json['balance'].toString(),
      status: FeeDueStatus.fromWire(json['status'] as String),
      isOverdue: json['is_overdue'] as bool? ?? false,
      cancelledReason: json['cancelled_reason'] as String?,
      isLateFine: json['kind'] == 'late_fine',
      fineForDueId: json['fine_for_due_id'] as int?,
      waiveReason: json['waive_reason'] as String?,
      waivedAt: json['waived_at'] is String ? DateTime.tryParse(json['waived_at'] as String)?.toLocal() : null,
    );
  }

  final int id;
  final String feeHeadName;
  final int? feeHeadId;
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

  /// A late fine (F4): added once to an installment still unpaid after the
  /// grace days. Never discounted; can be waived.
  final bool isLateFine;

  /// The installment a fine was added to.
  final int? fineForDueId;
  final String? waiveReason;
  final DateTime? waivedAt;

  bool get isCancelled => status == FeeDueStatus.cancelled;
  bool get isWaived => status == FeeDueStatus.waived;

  /// Still owed, so it can be paid or forgiven.
  bool get isOpen => (status == FeeDueStatus.pending || status == FeeDueStatus.partial) && !isCoveredByDiscount;

  /// A discount takes the whole of what is left. The server keeps such a due
  /// pending rather than paid, so that ending the discount charges it again
  /// (docs/fees.md, F4) - but nothing is owed on it, so it cannot be paid or
  /// waived, and it reads as covered.
  bool get isCoveredByDiscount =>
      (status == FeeDueStatus.pending || status == FeeDueStatus.partial) &&
      (centsOf(discountAmount) ?? 0) > 0 &&
      (centsOf(balance) ?? 1) == 0;
}

class FeeTotals {
  const FeeTotals({
    required this.charged,
    required this.discount,
    required this.paid,
    required this.balance,
    required this.overdue,
    this.waived = '0.00',
  });

  factory FeeTotals.fromJson(Map<String, dynamic> json) => FeeTotals(
    charged: json['charged'].toString(),
    discount: json['discount'].toString(),
    paid: json['paid'].toString(),
    balance: json['balance'].toString(),
    overdue: json['overdue'].toString(),
    waived: json['waived']?.toString() ?? '0.00',
  );

  final String charged;
  final String discount;
  final String paid;
  final String balance;
  final String overdue;

  /// What was forgiven (F4).
  final String waived;
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
    this.concessions = const [],
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
      concessions: [
        for (final row in json['concessions'] as List? ?? const []) FeeConcession.fromJson(row as Map<String, dynamic>),
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

  /// The discounts in force for this year (F4).
  final List<FeeConcession> concessions;

  /// The fee types this student is charged this year - what a discount can
  /// be given on.
  List<({int id, String name})> get feeHeads {
    final seen = <int, String>{};
    for (final due in dues) {
      if (!due.isLateFine && due.feeHeadId != null) seen[due.feeHeadId!] = due.feeHeadName;
    }
    return [for (final entry in seen.entries) (id: entry.key, name: entry.value)];
  }

  /// The installments a payment can go to, oldest first - those with
  /// something left to pay.
  List<FeeDue> get payable => [
    for (final due in dues)
      if (due.isOpen) due,
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

/// A discount on one student's fees for one year (docs/fees.md, F4): a fixed
/// amount or a percentage off each installment, of one fee type or all.
class FeeConcession {
  const FeeConcession({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.academicYearName,
    required this.isPercent,
    required this.value,
    required this.reason,
    required this.currencyCode,
    required this.duesAffected,
    this.className,
    this.feeHeadName,
    this.createdByName,
    this.createdAt,
    this.revokedAt,
  });

  factory FeeConcession.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>;
    DateTime? instant(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

    return FeeConcession(
      id: json['id'] as int,
      studentId: student['id'] as int,
      studentName: student['name'] as String,
      admissionNumber: student['admission_number'] as String,
      className: student['class_name'] as String?,
      academicYearName: (json['academic_year'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      feeHeadName: (json['fee_head'] as Map<String, dynamic>?)?['name'] as String?,
      isPercent: json['kind'] == 'percent',
      value: json['value'].toString(),
      reason: json['reason'] as String? ?? '',
      createdByName: (json['created_by'] as Map<String, dynamic>?)?['name'] as String?,
      createdAt: instant(json['created_at']),
      revokedAt: instant(json['revoked_at']),
      currencyCode: json['currency_code'] as String? ?? '',
      duesAffected: json['dues_affected'] as int? ?? 0,
    );
  }

  final int id;
  final int studentId;
  final String studentName;
  final String admissionNumber;
  final String? className;
  final String academicYearName;

  /// Null for every fee type.
  final String? feeHeadName;
  final bool isPercent;
  final String value;
  final String reason;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? revokedAt;
  final String currencyCode;
  final int duesAffected;

  bool get isRevoked => revokedAt != null;
}
