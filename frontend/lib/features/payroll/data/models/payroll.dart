import '../../../../core/models/user_role.dart';
import '../../../payments/data/models/payment.dart';

/// Payroll (Phase 19) - see docs/payroll.md.
///
/// Money arrives as strings with two decimals and is kept as the string it
/// came as; it is only turned into a number to be formatted. Day counts are
/// numbers and can be halves.

enum PayComponentType {
  earning('earning', 'Earning'),
  deduction('deduction', 'Deduction');

  const PayComponentType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PayComponentType fromApiValue(String value) =>
      PayComponentType.values.firstWhere((type) => type.apiValue == value);
}

enum PayrollRunStatus {
  draft('draft', 'Draft'),
  finalized('finalized', 'Finalized'),
  paid('paid', 'Paid');

  const PayrollRunStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PayrollRunStatus fromApiValue(String value) =>
      PayrollRunStatus.values.firstWhere((status) => status.apiValue == value);
}

enum PayslipStatus {
  unpaid('unpaid', 'Unpaid'),
  paid('paid', 'Paid');

  const PayslipStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PayslipStatus fromApiValue(String value) => PayslipStatus.values.firstWhere((s) => s.apiValue == value);
}

class SalaryComponent {
  const SalaryComponent({this.id, required this.type, required this.name, required this.amount});

  factory SalaryComponent.fromJson(Map<String, dynamic> json) {
    return SalaryComponent(
      id: json['id'] as int?,
      type: PayComponentType.fromApiValue(json['type'] as String),
      name: json['name'] as String,
      amount: json['amount'] as String,
    );
  }

  final int? id;
  final PayComponentType type;
  final String name;
  final String amount;

  Map<String, dynamic> toJson() => {'type': type.apiValue, 'name': name, 'amount': amount};
}

class Salary {
  const Salary({
    required this.basicSalary,
    required this.currencyCode,
    required this.components,
    required this.totalEarnings,
    required this.totalDeductions,
    required this.grossMonthly,
    required this.netMonthly,
    this.updatedByName,
    this.updatedAt,
  });

  factory Salary.fromJson(Map<String, dynamic> json) {
    return Salary(
      basicSalary: json['basic_salary'] as String,
      currencyCode: json['currency_code'] as String,
      components: [
        for (final component in json['components'] as List) SalaryComponent.fromJson(component as Map<String, dynamic>),
      ],
      totalEarnings: json['total_earnings'] as String,
      totalDeductions: json['total_deductions'] as String,
      grossMonthly: json['gross_monthly'] as String,
      netMonthly: json['net_monthly'] as String,
      updatedByName: json['updated_by_name'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  final String basicSalary;
  final String currencyCode;
  final List<SalaryComponent> components;
  final String totalEarnings;
  final String totalDeductions;
  final String grossMonthly;
  final String netMonthly;
  final String? updatedByName;
  final String? updatedAt;
}

/// One row of the salary screen: an employee, and what they are paid if it
/// has been set.
class EmployeeSalary {
  const EmployeeSalary({
    required this.staffProfileId,
    required this.employeeId,
    required this.name,
    required this.role,
    required this.schoolId,
    required this.schoolName,
    required this.schoolCurrencyCode,
    this.designation,
    this.departmentName,
    this.salary,
  });

  factory EmployeeSalary.fromJson(Map<String, dynamic> json) {
    return EmployeeSalary(
      staffProfileId: json['staff_profile_id'] as int,
      employeeId: json['employee_id'] as String,
      name: json['name'] as String,
      role: UserRole.fromApiValue(json['role'] as String),
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String,
      schoolCurrencyCode: json['school_currency_code'] as String,
      designation: json['designation'] as String?,
      departmentName: json['department_name'] as String?,
      salary: json['salary'] == null ? null : Salary.fromJson(json['salary'] as Map<String, dynamic>),
    );
  }

  final int staffProfileId;
  final String employeeId;
  final String name;
  final UserRole role;
  final int schoolId;
  final String schoolName;
  final String schoolCurrencyCode;
  final String? designation;
  final String? departmentName;
  final Salary? salary;
}

class MissingSalary {
  const MissingSalary({
    required this.staffProfileId,
    required this.employeeId,
    required this.name,
    required this.reason,
  });

  factory MissingSalary.fromJson(Map<String, dynamic> json) {
    return MissingSalary(
      staffProfileId: json['staff_profile_id'] as int,
      employeeId: json['employee_id'] as String,
      name: json['name'] as String,
      reason: json['reason'] as String,
    );
  }

  final int staffProfileId;
  final String employeeId;
  final String name;
  final String reason;
}

class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.year,
    required this.month,
    required this.periodLabel,
    required this.status,
    required this.currencyCode,
    required this.workingDays,
    required this.employees,
    required this.paidCount,
    required this.unpaidCount,
    required this.grossTotal,
    required this.deductionsTotal,
    required this.netTotal,
    this.generatedByName,
    this.finalizedByName,
    this.finalizedAt,
    this.missingSalaries = const [],
  });

  factory PayrollRun.fromJson(Map<String, dynamic> json) {
    return PayrollRun(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String,
      year: json['year'] as int,
      month: json['month'] as int,
      periodLabel: json['period_label'] as String,
      status: PayrollRunStatus.fromApiValue(json['status'] as String),
      currencyCode: json['currency_code'] as String,
      workingDays: json['working_days'] as int,
      employees: json['employees'] as int,
      paidCount: json['paid_count'] as int,
      unpaidCount: json['unpaid_count'] as int,
      grossTotal: json['gross_total'] as String,
      deductionsTotal: json['deductions_total'] as String,
      netTotal: json['net_total'] as String,
      generatedByName: json['generated_by_name'] as String?,
      finalizedByName: json['finalized_by_name'] as String?,
      finalizedAt: json['finalized_at'] as String?,
      missingSalaries: [
        for (final row in (json['missing_salaries'] as List?) ?? const [])
          MissingSalary.fromJson(row as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final int schoolId;
  final String schoolName;
  final int year;
  final int month;
  final String periodLabel;
  final PayrollRunStatus status;
  final String currencyCode;
  final int workingDays;
  final int employees;
  final int paidCount;
  final int unpaidCount;
  final String grossTotal;
  final String deductionsTotal;
  final String netTotal;
  final String? generatedByName;
  final String? finalizedByName;
  final String? finalizedAt;
  final List<MissingSalary> missingSalaries;

  bool get isDraft => status == PayrollRunStatus.draft;
}

class PayslipLine {
  const PayslipLine({
    required this.id,
    required this.type,
    required this.name,
    required this.amount,
    required this.isAdjustment,
    this.fullAmount,
    this.note,
    this.createdByName,
  });

  factory PayslipLine.fromJson(Map<String, dynamic> json) {
    return PayslipLine(
      id: json['id'] as int,
      type: PayComponentType.fromApiValue(json['type'] as String),
      name: json['name'] as String,
      amount: json['amount'] as String,
      isAdjustment: json['is_adjustment'] as bool,
      fullAmount: json['full_amount'] as String?,
      note: json['note'] as String?,
      createdByName: json['created_by_name'] as String?,
    );
  }

  final int id;
  final PayComponentType type;
  final String name;
  final String amount;
  final bool isAdjustment;

  /// The monthly figure before pro-rating; null for an adjustment.
  final String? fullAmount;
  final String? note;
  final String? createdByName;
}

class Payslip {
  const Payslip({
    required this.id,
    required this.payrollRunId,
    required this.periodLabel,
    required this.runStatus,
    required this.schoolName,
    required this.staffProfileId,
    required this.employeeName,
    required this.employeeCode,
    required this.currencyCode,
    required this.workingDays,
    required this.paidDays,
    required this.absentDays,
    required this.halfDays,
    required this.unmarkedDays,
    required this.grossEarnings,
    required this.totalDeductions,
    required this.netPay,
    required this.shortfall,
    required this.status,
    this.designation,
    this.departmentName,
    this.paidOn,
    this.paymentMode,
    this.paymentReference,
    this.emailedAt,
    this.lines = const [],
  });

  factory Payslip.fromJson(Map<String, dynamic> json) {
    final mode = json['payment_mode'] as String?;

    return Payslip(
      id: json['id'] as int,
      payrollRunId: json['payroll_run_id'] as int,
      periodLabel: json['period_label'] as String,
      runStatus: PayrollRunStatus.fromApiValue(json['run_status'] as String),
      schoolName: json['school_name'] as String,
      staffProfileId: json['staff_profile_id'] as int,
      employeeName: json['employee_name'] as String,
      employeeCode: json['employee_code'] as String,
      currencyCode: json['currency_code'] as String,
      workingDays: (json['working_days'] as num).toDouble(),
      paidDays: (json['paid_days'] as num).toDouble(),
      absentDays: (json['absent_days'] as num).toDouble(),
      halfDays: json['half_days'] as int,
      unmarkedDays: json['unmarked_days'] as int,
      grossEarnings: json['gross_earnings'] as String,
      totalDeductions: json['total_deductions'] as String,
      netPay: json['net_pay'] as String,
      shortfall: json['shortfall'] as String,
      status: PayslipStatus.fromApiValue(json['status'] as String),
      designation: json['designation'] as String?,
      departmentName: json['department_name'] as String?,
      paidOn: json['paid_on'] as String?,
      paymentMode: mode == null ? null : PaymentMode.fromApiValue(mode),
      paymentReference: json['payment_reference'] as String?,
      emailedAt: json['emailed_at'] as String?,
      lines: [
        for (final line in (json['lines'] as List?) ?? const []) PayslipLine.fromJson(line as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final int payrollRunId;
  final String periodLabel;
  final PayrollRunStatus runStatus;
  final String schoolName;
  final int staffProfileId;
  final String employeeName;
  final String employeeCode;
  final String currencyCode;
  final double workingDays;
  final double paidDays;
  final double absentDays;
  final int halfDays;
  final int unmarkedDays;
  final String grossEarnings;
  final String totalDeductions;
  final String netPay;
  final String shortfall;
  final PayslipStatus status;
  final String? designation;
  final String? departmentName;
  final String? paidOn;
  final PaymentMode? paymentMode;
  final String? paymentReference;
  final String? emailedAt;
  final List<PayslipLine> lines;

  bool get isPaid => status == PayslipStatus.paid;

  List<PayslipLine> linesOf(PayComponentType type) => [
    for (final line in lines)
      if (line.type == type) line,
  ];
}

/// "1.5" rather than "1.5000" or "2.0" - how a day count reads.
String formatDays(double days) => days == days.roundToDouble() ? days.toInt().toString() : days.toString();
