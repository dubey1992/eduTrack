import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'grade_scale_api.dart';
import 'models/grade_scale.dart';

final gradeScaleRepositoryProvider = Provider<GradeScaleRepository>(
  (ref) => GradeScaleRepository(ref.watch(gradeScaleApiProvider)),
);

class GradeScaleRepository {
  GradeScaleRepository(this._api);

  final GradeScaleApi _api;

  Future<PaginatedResponse<GradeScale>> listPage({int? schoolId, required int page, required int perPage}) {
    return _call(() => _api.list(schoolId: schoolId, page: page, perPage: perPage));
  }

  Future<GradeScale> create({
    int? schoolId,
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) {
    return _call(() => _api.create(schoolId: schoolId, name: name, isDefault: isDefault, bands: bands));
  }

  Future<GradeScale> update(
    int scaleId, {
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) {
    return _call(() => _api.update(scaleId, name: name, isDefault: isDefault, bands: bands));
  }

  Future<void> delete(int scaleId) => _call(() => _api.delete(scaleId));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
