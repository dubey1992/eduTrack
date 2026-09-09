import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';

import 'fake_pagination.dart';

class FakeAcademicYearRepository implements AcademicYearRepository {
  FakeAcademicYearRepository({List<AcademicYear>? years, this.failCreateWith}) : _years = years ?? [];

  final List<AcademicYear> _years;
  Failure? failCreateWith;

  List<AcademicYear> _filtered({int? schoolId}) {
    return schoolId == null ? _years : _years.where((y) => y.schoolId == schoolId).toList();
  }

  @override
  Future<List<AcademicYear>> list({int? schoolId}) async {
    return List.unmodifiable(_filtered(schoolId: schoolId));
  }

  @override
  Future<PaginatedResponse<AcademicYear>> listPage({int? schoolId, required int page, required int perPage}) async {
    return paginateFake(
      _filtered(schoolId: schoolId),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<AcademicYear> create({
    int? schoolId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required bool isCurrent,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final year = AcademicYear(
      id: _years.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      startDate: startDate,
      endDate: endDate,
      isCurrent: isCurrent,
    );
    _years.add(year);
    return year;
  }

  @override
  Future<AcademicYear> update(int academicYearId, {String? name, DateTime? startDate, DateTime? endDate}) async {
    final index = _years.indexWhere((y) => y.id == academicYearId);
    final existing = _years[index];
    final updated = AcademicYear(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      name: name ?? existing.name,
      startDate: startDate ?? existing.startDate,
      endDate: endDate ?? existing.endDate,
      isCurrent: existing.isCurrent,
    );
    _years[index] = updated;
    return updated;
  }

  @override
  Future<AcademicYear> setCurrent(int academicYearId) async {
    final index = _years.indexWhere((y) => y.id == academicYearId);
    for (var i = 0; i < _years.length; i++) {
      _years[i] = _years[i].copyWith(isCurrent: i == index);
    }
    return _years[index];
  }

  @override
  Future<void> delete(int academicYearId) async {
    _years.removeWhere((y) => y.id == academicYearId);
  }
}
