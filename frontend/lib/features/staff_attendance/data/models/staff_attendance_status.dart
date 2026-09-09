enum StaffAttendanceStatus {
  present('present', 'Present'),
  absent('absent', 'Absent'),
  leave('leave', 'Leave'),
  halfDay('half_day', 'Half Day');

  const StaffAttendanceStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static StaffAttendanceStatus fromApiValue(String value) =>
      StaffAttendanceStatus.values.firstWhere((s) => s.apiValue == value);
}
