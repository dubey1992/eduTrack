import '../../../../core/models/module_access.dart';
import '../../../../core/models/permission_level.dart';
import '../../../../core/models/user_role.dart';

enum UserStatus {
  active('active'),
  inactive('inactive');

  const UserStatus(this.apiValue);

  final String apiValue;

  static UserStatus fromApiValue(String value) => UserStatus.values.firstWhere((s) => s.apiValue == value);
}

class AppUser {
  const AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.email,
    required this.mobile,
    required this.role,
    required this.status,
    this.isSubAdmin = false,
    this.lockedUntil,
    this.access = const ModuleAccess.unspecified(),
    this.photoUrl,
    this.hasEmail = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      mobile: json['mobile'] as String?,
      role: UserRole.fromApiValue(json['role'] as String),
      status: UserStatus.fromApiValue(json['status'] as String),
      isSubAdmin: json['is_sub_admin'] as bool? ?? false,
      lockedUntil: json['locked_until'] as String?,
      access: ModuleAccess.fromJson(json),
      photoUrl: json['photo_url'] as String?,
      hasEmail: json['has_email'] as bool? ?? true,
    );
  }

  final int id;
  final String firstName;
  final String lastName;
  final String name;
  final String email;
  final String? mobile;
  final UserRole role;
  final UserStatus status;

  /// The profile photo's path relative to the API base, or null when there
  /// is none. See AuthenticatedUser.photoUrl.
  final String? photoUrl;

  /// False for a Bus Attendant added without an email address, whose [email]
  /// is then a placeholder that must not be shown. See StaffProfile.hasEmail.
  final bool hasEmail;

  /// True for a School Admin created by another School Admin - see
  /// AuthenticatedUser.isSubAdmin for the full explanation. Only ever
  /// true when [role] is schoolAdmin.
  final bool isSubAdmin;

  /// "Sub Admin" instead of the generic "School Admin" label when this
  /// account is one - the two share the same [role] and permissions
  /// everywhere else, so the list needs this to tell them apart.
  String get displayRoleLabel => isSubAdmin ? 'Sub Admin' : role.label;

  /// When a locked-out account may sign in again, or null when it is not
  /// locked (Phase 21: ten wrong passwords lock it for fifteen minutes). The
  /// API only sends a lock that is still running.
  final String? lockedUntil;

  bool get isLocked => lockedUntil != null;

  /// The same user payload serves the admin-users list and /me, so a row
  /// carries the account's permissions matrix and module switches too. See
  /// [ModuleAccess] for what a payload without them means.
  final ModuleAccess access;

  PermissionLevel level(String module) => access.level(module, role);

  bool canView(String module) => access.canView(module, role);

  bool canManage(String module) => access.canManage(module, role);

  bool moduleOn(String module) => access.moduleOn(module);

  AppUser copyWith({UserStatus? status, bool unlocked = false}) {
    return AppUser(
      id: id,
      firstName: firstName,
      lastName: lastName,
      name: name,
      email: email,
      mobile: mobile,
      role: role,
      status: status ?? this.status,
      isSubAdmin: isSubAdmin,
      lockedUntil: unlocked ? null : lockedUntil,
      access: access,
      photoUrl: photoUrl,
      hasEmail: hasEmail,
    );
  }
}
