import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';

import 'fake_pagination.dart';

class FakeStaffRepository implements StaffRepository {
  FakeStaffRepository({List<StaffProfile>? staff, this.failCreateWith}) : _staff = staff ?? [];

  final List<StaffProfile> _staff;
  Failure? failCreateWith;

  List<StaffProfile> _filtered({int? schoolId, int? departmentId, UserRole? role, String? search}) {
    final query = search?.trim().toLowerCase();
    return _staff
        .where((s) => schoolId == null || s.schoolId == schoolId)
        .where((s) => departmentId == null || s.departmentId == departmentId)
        .where((s) => role == null || s.role == role)
        .where((s) => query == null || query.isEmpty || s.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Future<List<StaffProfile>> list({int? schoolId, int? departmentId, UserRole? role, String? search}) async {
    return List.unmodifiable(_filtered(schoolId: schoolId, departmentId: departmentId, role: role, search: search));
  }

  @override
  Future<PaginatedResponse<StaffProfile>> listPage({
    int? schoolId,
    int? departmentId,
    UserRole? role,
    String? search,
    required int page,
    required int perPage,
  }) async {
    return paginateFake(
      _filtered(schoolId: schoolId, departmentId: departmentId, role: role, search: search),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<StaffProfile> create({
    required String firstName,
    required String lastName,
    required String email,
    String? mobile,
    required String password,
    required UserRole role,
    int? schoolId,
    required String employeeId,
    int? departmentId,
    String? designation,
    required DateTime joiningDate,
    String? address,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final profile = StaffProfile(
      id: _staff.length + 1,
      userId: _staff.length + 1,
      employeeId: employeeId,
      firstName: firstName,
      lastName: lastName,
      name: '$firstName $lastName',
      email: email,
      mobile: mobile,
      role: role,
      status: UserStatus.active,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      departmentId: departmentId,
      departmentName: departmentId != null ? 'Test Department' : null,
      designation: designation,
      joiningDate: joiningDate,
      address: address,
      classTeacherOf: const [],
    );
    _staff.add(profile);
    return profile;
  }

  @override
  Future<StaffProfile> update(
    int staffProfileId, {
    String? employeeId,
    int? departmentId,
    String? designation,
    DateTime? joiningDate,
    String? address,
  }) async {
    final index = _staff.indexWhere((s) => s.id == staffProfileId);
    final updated = _staff[index].copyWith(designation: designation, departmentId: departmentId);
    _staff[index] = updated;
    return updated;
  }
}
