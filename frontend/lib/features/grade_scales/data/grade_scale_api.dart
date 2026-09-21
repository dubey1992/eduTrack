import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/grade_scale.dart';

final gradeScaleApiProvider = Provider<GradeScaleApi>((ref) => GradeScaleApi(ref.watch(dioClientProvider)));

class GradeScaleApi {
  GradeScaleApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<GradeScale>> list({int? schoolId, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/grade-scales',
      queryParameters: {'school_id': ?schoolId, 'page': ?page, 'per_page': ?perPage},
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, GradeScale.fromJson);
  }

  Future<GradeScale> create({
    int? schoolId,
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) async {
    final response = await _dio.post(
      '/grade-scales',
      data: {
        'school_id': ?schoolId,
        'name': name,
        'is_default': isDefault,
        'bands': [for (final band in bands) band.toJson()],
      },
    );

    return GradeScale.fromJson(response.data as Map<String, dynamic>);
  }

  /// A PUT, not a PATCH: the bands are replaced as a set, so there is no
  /// partial edit of a scale.
  Future<GradeScale> update(
    int scaleId, {
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) async {
    final response = await _dio.put(
      '/grade-scales/$scaleId',
      data: {
        'name': name,
        'is_default': isDefault,
        'bands': [for (final band in bands) band.toJson()],
      },
    );

    return GradeScale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int scaleId) async {
    await _dio.delete('/grade-scales/$scaleId');
  }
}
