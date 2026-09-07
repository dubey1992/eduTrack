class AuthenticatedUser {
  const AuthenticatedUser({required this.id, required this.name, required this.email});

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    return AuthenticatedUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  final int id;
  final String name;
  final String email;
}
