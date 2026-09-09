import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';

import 'fake_pagination.dart';

class FakeSchoolClassRepository implements SchoolClassRepository {
  FakeSchoolClassRepository({
    List<SchoolClass>? classes,
    this.failCreateWith,
    this.failUpdateWith,
    this.failListPageWith,
    this.failAddSectionWith,
    this.failUpdateSectionWith,
  }) : _classes = classes ?? [];

  final List<SchoolClass> _classes;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failListPageWith;
  Failure? failAddSectionWith;
  Failure? failUpdateSectionWith;

  List<SchoolClass> _filtered({int? schoolId, int? academicYearId}) {
    return _classes
        .where(
          (c) =>
              (schoolId == null || c.schoolId == schoolId) &&
              (academicYearId == null || c.academicYearId == academicYearId),
        )
        .toList();
  }

  @override
  Future<List<SchoolClass>> list({int? schoolId, int? academicYearId}) async {
    return List.unmodifiable(_filtered(schoolId: schoolId, academicYearId: academicYearId));
  }

  @override
  Future<PaginatedResponse<SchoolClass>> listPage({
    int? schoolId,
    int? academicYearId,
    required int page,
    required int perPage,
  }) async {
    if (failListPageWith != null) throw failListPageWith!;

    return paginateFake(
      _filtered(schoolId: schoolId, academicYearId: academicYearId),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<SchoolClass> create({
    int? schoolId,
    required int academicYearId,
    required String name,
    required int level,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final schoolClass = SchoolClass(
      id: _classes.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      academicYearId: academicYearId,
      academicYearName: 'Test Year',
      name: name,
      level: level,
      sections: const [],
    );
    _classes.add(schoolClass);
    return schoolClass;
  }

  @override
  Future<SchoolClass> update(int schoolClassId, {String? name, int? level}) async {
    if (failUpdateWith != null) throw failUpdateWith!;

    final index = _classes.indexWhere((c) => c.id == schoolClassId);
    final existing = _classes[index];
    final updated = SchoolClass(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      academicYearId: existing.academicYearId,
      academicYearName: existing.academicYearName,
      name: name ?? existing.name,
      level: level ?? existing.level,
      sections: existing.sections,
    );
    _classes[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(int schoolClassId) async {
    _classes.removeWhere((c) => c.id == schoolClassId);
  }

  @override
  Future<ClassSection> addSection({
    required int schoolClassId,
    required String name,
    String? roomNumber,
    int? classTeacherId,
  }) async {
    if (failAddSectionWith != null) throw failAddSectionWith!;

    final index = _classes.indexWhere((c) => c.id == schoolClassId);
    final section = ClassSection(
      id: _classes[index].sections.length + 1,
      schoolClassId: schoolClassId,
      name: name,
      roomNumber: roomNumber,
      classTeacherId: classTeacherId,
      classTeacherName: classTeacherId != null ? 'Test Teacher' : null,
    );
    _classes[index] = SchoolClass(
      id: _classes[index].id,
      schoolId: _classes[index].schoolId,
      schoolName: _classes[index].schoolName,
      academicYearId: _classes[index].academicYearId,
      academicYearName: _classes[index].academicYearName,
      name: _classes[index].name,
      level: _classes[index].level,
      sections: [..._classes[index].sections, section],
    );
    return section;
  }

  @override
  Future<ClassSection> updateSection(int sectionId, {String? name, String? roomNumber, int? classTeacherId}) async {
    if (failUpdateSectionWith != null) throw failUpdateSectionWith!;

    for (var i = 0; i < _classes.length; i++) {
      final schoolClass = _classes[i];
      final sectionIndex = schoolClass.sections.indexWhere((s) => s.id == sectionId);
      if (sectionIndex == -1) continue;

      final existing = schoolClass.sections[sectionIndex];
      final updated = ClassSection(
        id: existing.id,
        schoolClassId: existing.schoolClassId,
        name: name ?? existing.name,
        roomNumber: roomNumber,
        classTeacherId: classTeacherId,
        classTeacherName: classTeacherId != null ? 'Test Teacher' : null,
      );
      final sections = [...schoolClass.sections];
      sections[sectionIndex] = updated;
      _classes[i] = SchoolClass(
        id: schoolClass.id,
        schoolId: schoolClass.schoolId,
        schoolName: schoolClass.schoolName,
        academicYearId: schoolClass.academicYearId,
        academicYearName: schoolClass.academicYearName,
        name: schoolClass.name,
        level: schoolClass.level,
        sections: sections,
      );
      return updated;
    }
    throw StateError('Section $sectionId not found');
  }

  @override
  Future<void> deleteSection(int sectionId) async {
    for (var i = 0; i < _classes.length; i++) {
      final schoolClass = _classes[i];
      if (schoolClass.sections.any((s) => s.id == sectionId)) {
        _classes[i] = SchoolClass(
          id: schoolClass.id,
          schoolId: schoolClass.schoolId,
          schoolName: schoolClass.schoolName,
          academicYearId: schoolClass.academicYearId,
          academicYearName: schoolClass.academicYearName,
          name: schoolClass.name,
          level: schoolClass.level,
          sections: schoolClass.sections.where((s) => s.id != sectionId).toList(),
        );
      }
    }
  }
}
