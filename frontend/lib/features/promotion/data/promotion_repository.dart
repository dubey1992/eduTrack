import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/promotion_batch.dart';
import 'models/promotion_preview.dart';
import 'promotion_api.dart';

final promotionRepositoryProvider = Provider<PromotionRepository>(
  (ref) => PromotionRepository(ref.watch(promotionApiProvider)),
);

class PromotionRepository {
  PromotionRepository(this._api);

  final PromotionApi _api;

  Future<PromotionPreview> preview({
    required int classSectionId,
    required int toAcademicYearId,
    int? toClassSectionId,
  }) async {
    try {
      return await _api.preview(
        classSectionId: classSectionId,
        toAcademicYearId: toAcademicYearId,
        toClassSectionId: toClassSectionId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PromotionBatch> run({
    required int classSectionId,
    required int toAcademicYearId,
    int? toClassSectionId,
    required Map<int, String> outcomes,
  }) {
    return _call(
      () => _api.run(
        classSectionId: classSectionId,
        toAcademicYearId: toAcademicYearId,
        toClassSectionId: toClassSectionId,
        outcomes: outcomes,
      ),
    );
  }

  Future<PaginatedResponse<PromotionBatch>> history({int? page, int? perPage, int? academicYearId}) {
    return _call(() => _api.history(page: page, perPage: perPage, academicYearId: academicYearId));
  }

  Future<PromotionBatch> batch(int batchId) => _call(() => _api.batch(batchId));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
