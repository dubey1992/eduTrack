enum LeaveStatus {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  const LeaveStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LeaveStatus fromApiValue(String value) => LeaveStatus.values.firstWhere((s) => s.apiValue == value);
}
