import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
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
}
