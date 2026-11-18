/// Money paid to an employee ahead of their pay, taken back from their
/// payslips month by month (docs/dashboard.md, D4).
///
/// Every figure comes from the server, which reads what has been recovered
/// off finalized payslips - the app never adds it up itself.
library;

enum StaffAdvanceStatus {
  active('active', 'Being recovered'),
  repaid('repaid', 'Repaid'),
  cancelled('cancelled', 'Cancelled');

  const StaffAdvanceStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static StaffAdvanceStatus fromApiValue(String value) =>
      values.firstWhere((status) => status.apiValue == value, orElse: () => active);
}

class StaffAdvance {
  const StaffAdvance({
    required this.id,
    required this.staffProfileId,
    required this.employeeName,
    required this.employeeCode,
    required this.amount,
    required this.currencyCode,
    required this.paidOn,
    required this.paymentModeLabel,
    required this.monthlyRecovery,
    required this.recoveryStartsLabel,
    required this.reason,
    required this.status,
    required this.recovered,
    required this.pending,
    required this.remaining,
    required this.canCancel,
    this.reference,
    this.cancelReason,
    this.recoveries = const [],
  });

  factory StaffAdvance.fromJson(Map<String, dynamic> json) {
    return StaffAdvance(
      id: json['id'] as int,
      staffProfileId: json['staff_profile_id'] as int,
      employeeName: json['employee_name'] as String,
      employeeCode: json['employee_code'] as String?,
      amount: json['amount'] as String,
      currencyCode: json['currency_code'] as String,
      paidOn: DateTime.parse(json['paid_on'] as String),
      paymentModeLabel: json['payment_mode_label'] as String? ?? json['payment_mode'] as String,
      reference: json['reference'] as String?,
      monthlyRecovery: json['monthly_recovery'] as String,
      recoveryStartsLabel: json['recovery_starts_label'] as String,
      reason: json['reason'] as String,
      status: StaffAdvanceStatus.fromApiValue(json['status'] as String),
      recovered: json['recovered'] as String,
      pending: json['pending'] as String,
      remaining: json['remaining'] as String,
      canCancel: json['can_cancel'] as bool? ?? false,
      cancelReason: json['cancel_reason'] as String?,
      recoveries: (json['recoveries'] as List<dynamic>? ?? const [])
          .map((row) => AdvanceRecovery.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  final int id;
  final int staffProfileId;
  final String employeeName;
  final String? employeeCode;

  /// Money as the server sends it: "3000.00", in [currencyCode].
  final String amount;
  final String currencyCode;
  final DateTime paidOn;
  final String paymentModeLabel;
  final String? reference;
  final String monthlyRecovery;

  /// "August 2026" - the first payroll month that takes it back.
  final String recoveryStartsLabel;
  final String reason;
  final StaffAdvanceStatus status;

  /// Taken back by finalized payslips.
  final String recovered;

  /// On a draft payroll not yet finalized - not recovered until it is.
  final String pending;
  final String remaining;
  final bool canCancel;
  final String? cancelReason;
  final List<AdvanceRecovery> recoveries;

  /// How much of it is back, 0 to 1, for the progress bar.
  double get progress {
    final whole = double.tryParse(amount) ?? 0;
    if (whole <= 0) return 0;

    return ((double.tryParse(recovered) ?? 0) / whole).clamp(0, 1).toDouble();
  }
}

/// One payslip's recovery of an advance.
class AdvanceRecovery {
  const AdvanceRecovery({
    required this.payslipId,
    required this.periodLabel,
    required this.runStatus,
    required this.amount,
  });

  factory AdvanceRecovery.fromJson(Map<String, dynamic> json) {
    return AdvanceRecovery(
      payslipId: json['payslip_id'] as int,
      periodLabel: json['period_label'] as String,
      runStatus: json['run_status'] as String,
      amount: json['amount'] as String,
    );
  }

  final int payslipId;
  final String periodLabel;
  final String runStatus;
  final String amount;

  bool get isPending => runStatus == 'draft';
}
