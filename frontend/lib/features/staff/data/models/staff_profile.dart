import '../../../../core/models/user_role.dart';
import '../../../users/data/models/app_user.dart';

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.userId,
    required this.employeeId,
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
  });

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      employeeId: json['employee_id'] as String,
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
    );
  }

  final int id;
  final int userId;
  final String employeeId;
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

  StaffProfile copyWith({
    UserStatus? status,
    String? designation,
    int? departmentId,
    String? departmentName,
    bool unlocked = false,
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
    );
  }
}
