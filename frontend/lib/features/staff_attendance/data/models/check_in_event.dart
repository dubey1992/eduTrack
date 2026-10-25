/// One check-in or check-out made from the phone, as the office sees it on
/// the web (`GET staff-attendance/check-ins`, docs/staff-check-in.md).
///
/// What the phone recorded at the tap, with how far from school it was. If
/// the office later corrected the day, the register shows the correction and
/// this still shows what the phone said.
class CheckInEvent {
  const CheckInEvent({
    required this.id,
    required this.staffProfileId,
    required this.name,
    required this.employeeId,
    required this.departmentName,
    required this.isCheckIn,
    required this.time,
    required this.distanceMetres,
  });

  factory CheckInEvent.fromJson(Map<String, dynamic> json) => CheckInEvent(
    id: json['id'] as int,
    staffProfileId: json['staff_profile_id'] as int,
    name: json['name'] as String,
    employeeId: json['employee_id'] as String,
    departmentName: json['department_name'] as String?,
    isCheckIn: json['kind'] == 'check_in',
    time: json['time'] as String?,
    distanceMetres: json['distance_m'] as int?,
  );

  final int id;
  final int staffProfileId;
  final String name;
  final String employeeId;
  final String? departmentName;
  final bool isCheckIn;

  /// `HH:mm` on the school's clock.
  final String? time;
  final int? distanceMetres;
}
