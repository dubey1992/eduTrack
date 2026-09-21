import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/academic_years/data/academic_term_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_term.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';

/// An in-memory stand-in for the terms API.
///
/// It keeps the server's own ordering - by sequence number - so a test that
/// adds a term out of order sees it land where the real list would put it.
class FakeAcademicTermRepository implements AcademicTermRepository {
  FakeAcademicTermRepository({List<AcademicTerm>? terms, this.failWith = const {}}) : _terms = terms ?? [];

  final List<AcademicTerm> _terms;

  /// Keyed by method name: {'create': Failure(...)}.
  final Map<String, Failure> failWith;

  final List<String> calls = [];

  void _enter(String method) {
    calls.add(method);
    final failure = failWith[method];
    if (failure != null) throw failure;
  }

  @override
  Future<List<AcademicTerm>> listForYear(int academicYearId) async {
    _enter('listForYear');

    final mine = _terms.where((term) => term.academicYearId == academicYearId).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    return List.unmodifiable(mine);
  }

  @override
  Future<AcademicTerm> create({
    required int academicYearId,
    required String name,
    required int sequenceNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _enter('create');

    final term = AcademicTerm(
      id: _terms.length + 1,
      schoolId: 1,
      academicYearId: academicYearId,
      academicYearName: '2026-27',
      name: name,
      sequenceNumber: sequenceNumber,
      startDate: startDate,
      endDate: endDate,
    );
    _terms.add(term);

    return term;
  }

  @override
  Future<AcademicTerm> update(
    int termId, {
    String? name,
    int? sequenceNumber,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _enter('update');

    final index = _terms.indexWhere((term) => term.id == termId);
    final existing = _terms[index];
    final updated = AcademicTerm(
      id: existing.id,
      schoolId: existing.schoolId,
      academicYearId: existing.academicYearId,
      academicYearName: existing.academicYearName,
      name: name ?? existing.name,
      sequenceNumber: sequenceNumber ?? existing.sequenceNumber,
      startDate: startDate ?? existing.startDate,
      endDate: endDate ?? existing.endDate,
    );
    _terms[index] = updated;

    return updated;
  }

  @override
  Future<void> delete(int termId) async {
    _enter('delete');
    _terms.removeWhere((term) => term.id == termId);
  }
}

AcademicTerm fakeTerm({
  int id = 1,
  int academicYearId = 1,
  String name = 'Term 1',
  int sequenceNumber = 1,
  DateTime? startDate,
  DateTime? endDate,
}) {
  return AcademicTerm(
    id: id,
    schoolId: 1,
    academicYearId: academicYearId,
    academicYearName: '2026-27',
    name: name,
    sequenceNumber: sequenceNumber,
    startDate: startDate ?? DateTime(2026, 4, 1),
    endDate: endDate ?? DateTime(2026, 8, 31),
  );
}

AcademicYear fakeYear({int id = 1, String name = '2026-27', bool isCurrent = true}) {
  return AcademicYear(
    id: id,
    schoolId: 1,
    schoolName: 'Test School',
    name: name,
    startDate: DateTime(2026, 4, 1),
    endDate: DateTime(2027, 3, 31),
    isCurrent: isCurrent,
  );
}
