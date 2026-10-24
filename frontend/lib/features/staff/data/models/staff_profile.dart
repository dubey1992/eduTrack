import '../../../../core/models/user_role.dart';
import '../../../users/data/models/app_user.dart';

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.userId,
    required this.employeeId,
    this.biometricUserId,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.email,
    required this.mobile,
    required this.role,
    required this.status,
    required this.schoolId,
    required this.schoolName,
    required this.departmentId,
    required this.departmentName,
    required this.designation,
    required this.joiningDate,
    required this.address,
    required this.classTeacherOf,
    this.lockedUntil,
    this.photoUrl,
    this.hasEmail = true,
    this.driverId,
    this.licenceNumber,
    this.licenceExpiry,
  });

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      employeeId: json['employee_id'] as String,
      biometricUserId: json['biometric_user_id'] as String?,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      mobile: json['mobile'] as String?,
      role: UserRole.fromApiValue(json['role'] as String),
      status: UserStatus.fromApiValue(json['status'] as String),
      lockedUntil: json['locked_until'] as String?,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      departmentId: json['department_id'] as int?,
      departmentName: json['department_name'] as String?,
      designation: json['designation'] as String?,
      joiningDate: DateTime.parse(json['joining_date'] as String),
      address: json['address'] as String?,
      classTeacherOf: (json['class_teacher_of'] as List).cast<String>(),
      photoUrl: json['photo_url'] as String?,
      hasEmail: json['has_email'] as bool? ?? true,
      driverId: json['driver_id'] as int?,
      licenceNumber: json['licence_number'] as String?,
      licenceExpiry: json['licence_expiry'] as String?,
    );
  }

  final int id;
  final int userId;
  final String employeeId;

  /// Their id on the school's fingerprint devices, or null for the
  /// many who are not enrolled on one (docs/biometric.md).
  final String? biometricUserId;
  final String firstName;
  final String lastName;
  final String name;
  final String email;
  final String? mobile;
  final UserRole role;
  final UserStatus status;

  /// When a locked-out account may sign in again, or null when it is not
  /// locked (Phase 21: ten wrong passwords lock it for fifteen minutes). The
  /// API only sends a lock that is still running.
  final String? lockedUntil;

  bool get isLocked => lockedUntil != null;
  final int schoolId;
  final String? schoolName;
  final int? departmentId;
  final String? departmentName;
  final String? designation;
  final DateTime joiningDate;
  final String? address;
  final List<String> classTeacherOf;

  /// The profile photo's path relative to the API base, or null when there
  /// is none. See AuthenticatedUser.photoUrl.
  final String? photoUrl;

  /// False for a Bus Attendant added without an email address: [email] then
  /// holds a placeholder nobody can receive mail at, and must never be shown
  /// as if it were an address. See docs/maps.md, "The Bus Attendant".
  final bool hasEmail;

  bool get isBusAttendant => role == UserRole.busAttendant;

  /// Drives or attends the bus: signs in by passcode, has a Sign-in panel.
  bool get isCrew => role.isCrew;
  bool get isDriver => role == UserRole.driver;

  /// The licence record a driver carries beside the employment one
  /// (docs/driver-app.md, D10). Null for everybody else.
  final int? driverId;
  final String? licenceNumber;

  /// ISO date, or null when the licence has no expiry on record.
  final String? licenceExpiry;

  StaffProfile copyWith({
    UserStatus? status,
    String? designation,
    int? departmentId,
    String? departmentName,
    bool unlocked = false,
    String? licenceNumber,
    String? licenceExpiry,
  }) {
    return StaffProfile(
      id: id,
      userId: userId,
      employeeId: employeeId,
      firstName: firstName,
      lastName: lastName,
      name: name,
      email: email,
      mobile: mobile,
      role: role,
      status: status ?? this.status,
      lockedUntil: unlocked ? null : lockedUntil,
      schoolId: schoolId,
      schoolName: schoolName,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      designation: designation ?? this.designation,
      joiningDate: joiningDate,
      address: address,
      classTeacherOf: classTeacherOf,
      photoUrl: photoUrl,
      hasEmail: hasEmail,
      driverId: driverId,
      licenceNumber: licenceNumber ?? this.licenceNumber,
      licenceExpiry: licenceExpiry ?? this.licenceExpiry,
    );
  }
}
