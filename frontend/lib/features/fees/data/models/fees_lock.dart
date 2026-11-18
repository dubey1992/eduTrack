/// The fee books' date lock (docs/dashboard.md, D3): nothing dated on or
/// before [lockedUntil] can be recorded - no receipt, cancellation,
/// discount, waiver, late fine or refund.
class FeesLock {
  const FeesLock({required this.schoolId, required this.lockedUntil, required this.today, required this.canChange});

  factory FeesLock.fromJson(Map<String, dynamic> json) {
    return FeesLock(
      schoolId: json['school_id'] as int,
      lockedUntil: json['locked_until'] is String ? DateTime.tryParse(json['locked_until'] as String) : null,
      today: DateTime.parse(json['today'] as String),
      canChange: json['can_change'] as bool? ?? false,
    );
  }

  final int schoolId;

  /// Null when nothing is locked. A date in the school's calendar.
  final DateTime? lockedUntil;

  /// Today at the school - the latest day that can be locked.
  final DateTime today;

  /// A School Admin or Accountant who manages this school's fees.
  final bool canChange;

  bool get isLocked => lockedUntil != null;

  /// Whether moving the lock to [until] reopens closed days, which needs a
  /// reason.
  bool reopens(DateTime? until) {
    final current = lockedUntil;
    if (current == null) return false;

    return until == null || until.isBefore(current);
  }
}
