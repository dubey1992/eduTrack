enum AttendanceStatus {
  present('present', 'Present'),
  absent('absent', 'Absent'),
  leave('leave', 'Leave');

  const AttendanceStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AttendanceStatus fromApiValue(String value) => AttendanceStatus.values.firstWhere((s) => s.apiValue == value);
}
