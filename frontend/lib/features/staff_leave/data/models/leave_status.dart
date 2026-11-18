enum LeaveStatus {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),

  /// Taken back by the applicant while still pending (docs/mobile-apps-review.md, 1.9).
  withdrawn('withdrawn', 'Withdrawn');

  const LeaveStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LeaveStatus fromApiValue(String value) => LeaveStatus.values.firstWhere((s) => s.apiValue == value);
}
