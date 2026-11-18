import 'leave_type.dart';

/// The person's own leave over the school's year - GET /leaves/mine/taken
/// (docs/mobile-apps-review.md, 1.9). In working days, as the leave-usage
/// report counts them. What was taken, not what is left: the school sets
/// no allowance to subtract it from.
class LeaveTaken {
  const LeaveTaken({
    required this.label,
    required this.from,
    required this.to,
    required this.days,
    required this.totalDays,
    required this.pendingRequests,
  });

  factory LeaveTaken.fromJson(Map<String, dynamic> json) {
    return LeaveTaken(
      label: json['label'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      days: {
        for (final row in (json['types'] as List).cast<Map<String, dynamic>>())
          LeaveType.fromApiValue(row['leave_type'] as String): (row['days'] as num).toDouble(),
      },
      totalDays: (json['total_days'] as num).toDouble(),
      pendingRequests: json['pending_requests'] as int,
    );
  }

  /// The academic year's name ("2026-27"), or the calendar year.
  final String label;
  final String from;
  final String to;
  final Map<LeaveType, double> days;
  final double totalDays;
  final int pendingRequests;
}
