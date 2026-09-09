import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';

class FakeUserRepository implements UserRepository {
  FakeUserRepository({List<AppUser>? users, this.failCreateWith, this.failUpdateWith}) : _users = users ?? [];

  final List<AppUser> _users;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  int? lastListSchoolId;

  List<AppUser> _filtered({List<UserRole>? roles, String? status}) {
    return _users
        .where((u) => roles == null || roles.contains(u.role))
        .where((u) => status == null || u.status.apiValue == status)
        .toList();
  }

  @override
  Future<List<AppUser>> list({List<UserRole>? roles, int? schoolId, String? status}) async {
    lastListSchoolId = schoolId;
    return List.unmodifiable(_filtered(roles: roles, status: status));
  }

  @override
  Future<PaginatedResponse<AppUser>> listPage({
    List<UserRole>? roles,
    int? schoolId,
    String? status,
    required int page,
    required int perPage,
  }) async {
    lastListSchoolId = schoolId;
    final filtered = _filtered(roles: roles, status: status);
    final start = (page - 1) * perPage;
    final end = (start + perPage).clamp(start, filtered.length);
    final items = start >= filtered.length ? <AppUser>[] : filtered.sublist(start, end);

    return PaginatedResponse(
      items: items,
      currentPage: page,
      lastPage: (filtered.length / perPage).ceil().clamp(1, double.infinity).toInt(),
      total: filtered.length,
      perPage: perPage,
    );
  }

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
  Future<AppUser> update(
    int userId, {
    String? firstName,
    String? lastName,
    String? email,
    String? mobile,
    String? password,
    UserRole? role,
  }) async {
    if (failUpdateWith != null) throw failUpdateWith!;

    final index = _users.indexWhere((u) => u.id == userId);
    final existing = _users[index];
    final newFirstName = firstName ?? existing.firstName;
    final newLastName = lastName ?? existing.lastName;
    final updated = AppUser(
      id: existing.id,
      firstName: newFirstName,
      lastName: newLastName,
      name: '$newFirstName $newLastName',
      email: email ?? existing.email,
      mobile: mobile,
      role: role ?? existing.role,
      status: existing.status,
    );
    _users[index] = updated;
    return updated;
  }

  @override
  Future<AppUser> setActive(int userId, bool active) async {
    final index = _users.indexWhere((u) => u.id == userId);
    final updated = _users[index].copyWith(status: active ? UserStatus.active : UserStatus.inactive);
    _users[index] = updated;
    return updated;
  }
}
