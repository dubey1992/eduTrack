/// The stat cards the prototype's Staff Leave Management screen shows -
/// counted server-side across the actor's whole visible scope, not just the
/// current page (see `GET /leaves/summary`).
class StaffLeaveSummary {
  const StaffLeaveSummary({
    required this.pending,
    required this.approvedThisMonth,
    required this.rejected,
    required this.onLeaveToday,
  });

  factory StaffLeaveSummary.fromJson(Map<String, dynamic> json) {
    return StaffLeaveSummary(
      pending: json['pending'] as int,
      approvedThisMonth: json['approved_this_month'] as int,
      rejected: json['rejected'] as int,
      onLeaveToday: json['on_leave_today'] as int,
    );
  }

  final int pending;
  final int approvedThisMonth;
  final int rejected;
  final int onLeaveToday;
}
