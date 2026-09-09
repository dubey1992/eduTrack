import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';

import 'fake_pagination.dart';

class FakeSubjectRepository implements SubjectRepository {
  FakeSubjectRepository({List<Subject>? subjects, this.failCreateWith, this.failUpdateWith, this.failListPageWith})
    : _subjects = subjects ?? [];

  final List<Subject> _subjects;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failListPageWith;

  List<Subject> _filtered({int? schoolId, int? departmentId}) {
    return _subjects
        .where(
          (s) =>
              (schoolId == null || s.schoolId == schoolId) && (departmentId == null || s.departmentId == departmentId),
        )
        .toList();
  }

  @override
  Future<List<Subject>> list({int? schoolId, int? departmentId}) async {
    return List.unmodifiable(_filtered(schoolId: schoolId, departmentId: departmentId));
  }

  @override
  Future<PaginatedResponse<Subject>> listPage({
    int? schoolId,
    int? departmentId,
    required int page,
    required int perPage,
  }) async {
    if (failListPageWith != null) throw failListPageWith!;

    return paginateFake(
      _filtered(schoolId: schoolId, departmentId: departmentId),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<Subject> create({
    int? schoolId,
    required int departmentId,
    required String code,
    required String name,
    required int minClassLevel,
    required int maxClassLevel,
    int? leadTeacherId,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final subject = Subject(
      id: _subjects.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      departmentId: departmentId,
      departmentName: 'Test Department',
      code: code,
      name: name,
      minClassLevel: minClassLevel,
      maxClassLevel: maxClassLevel,
      leadTeacherId: leadTeacherId,
      leadTeacherName: leadTeacherId != null ? 'Test Teacher' : null,
    );
    _subjects.add(subject);
    return subject;
  }

  @override
  Future<Subject> update(
    int subjectId, {
    int? departmentId,
    String? code,
    String? name,
    int? minClassLevel,
    int? maxClassLevel,
    int? leadTeacherId,
  }) async {
    if (failUpdateWith != null) throw failUpdateWith!;

    final index = _subjects.indexWhere((s) => s.id == subjectId);
    final existing = _subjects[index];
    final updated = Subject(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      departmentId: departmentId ?? existing.departmentId,
      departmentName: existing.departmentName,
      code: code ?? existing.code,
      name: name ?? existing.name,
      minClassLevel: minClassLevel ?? existing.minClassLevel,
      maxClassLevel: maxClassLevel ?? existing.maxClassLevel,
      leadTeacherId: leadTeacherId,
      leadTeacherName: leadTeacherId != null ? 'Test Teacher' : null,
    );
    _subjects[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(int subjectId) async {
    _subjects.removeWhere((s) => s.id == subjectId);
  }
}
