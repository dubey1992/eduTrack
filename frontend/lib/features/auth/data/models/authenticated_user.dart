import '../../../../core/models/user_role.dart';
import '../../../../core/utils/school_clock.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isSubAdmin = false,
    this.mustChangePassword = false,
    SchoolClock? clock,
  }) : _clock = clock;

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
      isSubAdmin: json['is_sub_admin'] as bool? ?? false,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }

  final int id;
  final String name;
  final String email;
  final UserRole role;

  final SchoolClock? _clock;

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
}
