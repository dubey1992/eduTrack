import '../../../../core/models/module_access.dart';
import '../../../../core/models/permission_level.dart';
import '../../../../core/models/user_role.dart';
import '../../../schools/data/models/working_week.dart';
import '../../../../core/utils/school_clock.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.schoolId,
    this.isSubAdmin = false,
    this.mustChangePassword = false,
    this.managesBranches = false,
    this.access = const ModuleAccess.unspecified(),
    this.photoUrl,
    WorkingWeek? workingDays,
    SchoolClock? clock,
    // The fields are private and the parameters are not. An initializing
    // formal would make callers write `_clock:`, leaking the underscore into
    // the public API - so the lint's fix is worse than the lint.
    // ignore: prefer_initializing_formals
  }) : _workingDays = workingDays,
       // ignore: prefer_initializing_formals
       _clock = clock;

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    return AuthenticatedUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      role: UserRole.fromApiValue(json['role'] as String),
      // The school's timezone and its current time, so nothing on the client
      // has to ask the browser what day it is.
      clock: SchoolClock.fromSession(
        timezone: json['timezone'] as String? ?? 'UTC',
        currentTime: json['current_time'] as String? ?? '',
      ),
      schoolId: json['school_id'] as int?,
      isSubAdmin: json['is_sub_admin'] as bool? ?? false,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      managesBranches: json['manages_branches'] as bool? ?? false,
      access: ModuleAccess.fromJson(json),
      photoUrl: json['photo_url'] as String?,
      workingDays: WorkingWeek.fromApiValue(json['working_days']),
    );
  }

  final int id;

  /// The school this account belongs to. Null for a Super Admin, who
  /// belongs to the platform rather than to a school.
  final int? schoolId;

  final String name;
  final String email;
  final UserRole role;

  /// Where the profile photo is served, relative to the API base (for
  /// example `/users/12/photo?v=ab12cd34`), or null when there is none. It
  /// changes whenever the photo does, so it doubles as a cache key.
  final String? photoUrl;

  final SchoolClock? _clock;
  final WorkingWeek? _workingDays;

  /// The days this user's school runs. A Super Admin belongs to no
  /// school and carries the default week; the screens that let them act
  /// on another school read that school's own.
  WorkingWeek get workingDays => _workingDays ?? WorkingWeek.mondayToFriday();

  /// What day it is at this user's school. A Super Admin belongs to no
  /// school and carries the platform's zone instead.
  ///
  /// Falls back to the device clock only when the session payload carried no
  /// timezone at all, which in practice means a stubbed user in a test.
  SchoolClock get clock => _clock ?? SchoolClock.device();

  /// True for a School Admin created by another School Admin (a "Sub
  /// Admin") - same role and permissions everywhere else, but they can't
  /// create or manage any admin account themselves. Always false for every
  /// other role. See the backend's UserPolicy::create().
  final bool isSubAdmin;

  /// True for an account created by a bulk import, which was handed a
  /// generated password. The router keeps them on the change-password
  /// screen until they pick one of their own.
  final bool mustChangePassword;

  /// True when this account answers for more than one school - an admin of a
  /// school that belongs to a group. Sent by the server, because the role
  /// alone cannot tell you: a School Admin spans a group or a single school
  /// depending on whether their school has branches at all.
  ///
  /// Mirrors the backend's SchoolScope::coversAGroup().
  final bool managesBranches;

  /// True when "my school" is ambiguous for this user, so a form has to ask
  /// which one. A Super Admin belongs to no school; an admin in a group
  /// belongs to several.
  ///
  /// Mirrors the backend's SchoolScope::defaultSchoolId() being null, which
  /// is what makes school_id a required field on the request.
  bool get picksSchool => role == UserRole.superAdmin || managesBranches;

  /// The permissions matrix and module switches as /me sent them. A payload
  /// without them - older API responses, role-only fixtures - falls back to
  /// the platform defaults; see [ModuleAccess].
  final ModuleAccess access;

  PermissionLevel level(String module) => access.level(module, role);

  /// The module is on for this school and the level is view or manage.
  bool canView(String module) => access.canView(module, role);

  /// The module is on for this school and the level is manage - what every
  /// Add, Edit, Delete, Approve or Submit control asks before it shows.
  bool canManage(String module) => access.canManage(module, role);

  /// Whether the module is switched on for this user's school.
  bool moduleOn(String module) => access.moduleOn(module);
}
