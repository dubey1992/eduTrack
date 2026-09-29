import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/promotion_batch.dart';
import 'models/promotion_preview.dart';

final promotionApiProvider = Provider<PromotionApi>((ref) => PromotionApi(ref.watch(dioClientProvider)));

/// Class promotion (docs/promotion.md): the preview, which writes nothing,
/// the run, which does it all in one transaction, and the history of what
/// has been done.
class PromotionApi {
  PromotionApi(this._dio);

  final Dio _dio;

  Future<PromotionPreview> preview({
    required int classSectionId,
    required int toAcademicYearId,
    int? toClassSectionId,
  }) async {
    final response = await _dio.get(
      '/promotions/preview',
      queryParameters: {
        'class_section_id': classSectionId,
        'to_academic_year_id': toAcademicYearId,
        'to_class_section_id': ?toClassSectionId,
      },
    );

    return PromotionPreview.fromJson(response.data as Map<String, dynamic>);
  }

  /// Runs one batch. Every student is named: the server acts on what the
  /// administrator decided, not on what the defaults would be.
  Future<PromotionBatch> run({
    required int classSectionId,
    required int toAcademicYearId,
    int? toClassSectionId,
    required Map<int, String> outcomes,
  }) async {
    final response = await _dio.post(
      '/promotions',
      data: {
        'class_section_id': classSectionId,
        'to_academic_year_id': toAcademicYearId,
        'to_class_section_id': ?toClassSectionId,
        'outcomes': [
          for (final entry in outcomes.entries) {'student_id': entry.key, 'outcome': entry.value},
        ],
      },
    );

    return PromotionBatch.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<PromotionBatch>> history({int? page, int? perPage, int? academicYearId}) async {
    final response = await _dio.get(
      '/promotions',
      queryParameters: {'page': ?page, 'per_page': ?perPage, 'academic_year_id': ?academicYearId},
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, PromotionBatch.fromJson);
  }

  Future<PromotionBatch> batch(int batchId) async {
    final response = await _dio.get('/promotions/$batchId');

    return PromotionBatch.fromJson(response.data as Map<String, dynamic>);
  }
}
