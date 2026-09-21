import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/grade_scales/data/grade_scale_repository.dart';
import 'package:edutrack_app/features/grade_scales/data/models/grade_scale.dart';

import 'fake_pagination.dart';

/// An in-memory stand-in for the grade scale API.
///
/// It keeps the server's two habits that the screens depend on: the default
/// scale sorts first, and a school's first scale is its default whatever the
/// request asked for.
class FakeGradeScaleRepository implements GradeScaleRepository {
  FakeGradeScaleRepository({List<GradeScale>? scales, this.failWith = const {}}) : _scales = scales ?? [];

  final List<GradeScale> _scales;

  /// Keyed by method name: {'create': Failure(...)}.
  final Map<String, Failure> failWith;

  final List<String> calls = [];

  /// What the last save sent, so a test can assert the bands that went out.
  List<GradeBand> lastBands = const [];

  void _enter(String method) {
    calls.add(method);
    final failure = failWith[method];
    if (failure != null) throw failure;
  }

  @override
  Future<PaginatedResponse<GradeScale>> listPage({int? schoolId, required int page, required int perPage}) async {
    _enter('listPage');

    final visible = schoolId == null ? _scales : _scales.where((scale) => scale.schoolId == schoolId).toList();
    final sorted = [...visible]
      ..sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return paginateFake(sorted, page: page, perPage: perPage);
  }

  @override
  Future<GradeScale> create({
    int? schoolId,
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) async {
    _enter('create');
    lastBands = bands;

    final scale = GradeScale(
      id: _scales.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      isDefault: isDefault || _scales.isEmpty,
      bands: bands,
    );
    _scales.add(scale);

    return scale;
  }

  @override
  Future<GradeScale> update(
    int scaleId, {
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) async {
    _enter('update');
    lastBands = bands;

    final index = _scales.indexWhere((scale) => scale.id == scaleId);
    final existing = _scales[index];
    final updated = GradeScale(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      name: name,
      isDefault: isDefault || existing.isDefault,
      bands: bands,
    );
    _scales[index] = updated;

    return updated;
  }

  @override
  Future<void> delete(int scaleId) async {
    _enter('delete');
    _scales.removeWhere((scale) => scale.id == scaleId);
  }
}

GradeBand fakeBand({
  int? id = 1,
  String label = 'Pass',
  String min = '33.00',
  String max = '100.00',
  bool isFailing = false,
}) {
  return GradeBand(id: id, label: label, minPercentage: min, maxPercentage: max, isFailing: isFailing);
}

GradeScale fakeGradeScale({
  int id = 1,
  String name = 'Secondary',
  bool isDefault = true,
  List<GradeBand>? bands,
  int schoolId = 1,
}) {
  return GradeScale(
    id: id,
    schoolId: schoolId,
    schoolName: 'Test School',
    name: name,
    isDefault: isDefault,
    bands: bands ?? [fakeBand(id: 1), fakeBand(id: 2, label: 'Fail', min: '0.00', max: '32.00', isFailing: true)],
  );
}
