import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';

import 'fake_pagination.dart';

class FakeDepartmentRepository implements DepartmentRepository {
  FakeDepartmentRepository({List<Department>? departments, this.failCreateWith}) : _departments = departments ?? [];

  final List<Department> _departments;
  Failure? failCreateWith;

  List<Department> _filtered({int? schoolId}) {
    return schoolId == null ? _departments : _departments.where((d) => d.schoolId == schoolId).toList();
  }

  @override
  Future<List<Department>> list({int? schoolId}) async {
    return List.unmodifiable(_filtered(schoolId: schoolId));
  }

  @override
  Future<PaginatedResponse<Department>> listPage({int? schoolId, required int page, required int perPage}) async {
    return paginateFake(
      _filtered(schoolId: schoolId),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<Department> create({int? schoolId, required String name, int? hodUserId}) async {
    if (failCreateWith != null) throw failCreateWith!;

    final department = Department(
      id: _departments.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      hodUserId: hodUserId,
      hodName: hodUserId != null ? 'Test HOD' : null,
    );
    _departments.add(department);
    return department;
  }

  @override
  Future<Department> update(int departmentId, {String? name, int? hodUserId}) async {
    final index = _departments.indexWhere((d) => d.id == departmentId);
    final existing = _departments[index];
    final updated = Department(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      name: name ?? existing.name,
      hodUserId: hodUserId,
      hodName: hodUserId != null ? 'Test HOD' : null,
    );
    _departments[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(int departmentId) async {
    _departments.removeWhere((d) => d.id == departmentId);
  }
}
