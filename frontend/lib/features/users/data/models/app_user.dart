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

  AppUser copyWith({UserStatus? status}) {
    return AppUser(
      id: id,
      firstName: firstName,
      lastName: lastName,
      name: name,
      email: email,
      mobile: mobile,
      role: role,
      status: status ?? this.status,
    );
  }
}
