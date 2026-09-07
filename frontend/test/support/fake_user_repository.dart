import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';

class FakeUserRepository implements UserRepository {
  FakeUserRepository({List<AppUser>? users, this.failCreateWith}) : _users = users ?? [];

  final List<AppUser> _users;
  Failure? failCreateWith;

  @override
  Future<List<AppUser>> list() async => List.unmodifiable(_users);

  @override
  Future<AppUser> create({
    required String firstName,
    required String lastName,
    required String email,
    String? mobile,
    required String password,
    required UserRole role,
    int? schoolId,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final user = AppUser(
      id: _users.length + 1,
      firstName: firstName,
      lastName: lastName,
      name: '$firstName $lastName',
      email: email,
      mobile: mobile,
      role: role,
      status: UserStatus.active,
    );
    _users.add(user);
    return user;
  }

  @override
  Future<AppUser> setActive(int userId, bool active) async {
    final index = _users.indexWhere((u) => u.id == userId);
    final updated = _users[index].copyWith(status: active ? UserStatus.active : UserStatus.inactive);
    _users[index] = updated;
    return updated;
  }
}
