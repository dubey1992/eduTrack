enum LeaveType {
  casual('casual', 'Casual Leave'),
  medical('medical', 'Medical Leave'),
  earned('earned', 'Earned Leave'),
  halfDay('half_day', 'Half Day');

  const LeaveType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LeaveType fromApiValue(String value) => LeaveType.values.firstWhere((t) => t.apiValue == value);
}
