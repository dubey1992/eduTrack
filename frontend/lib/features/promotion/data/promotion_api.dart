import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/promotion_preview.dart';

final promotionApiProvider = Provider<PromotionApi>((ref) => PromotionApi(ref.watch(dioClientProvider)));

/// Class promotion (docs/promotion.md). One endpoint so far: the preview,
/// which reads and writes nothing.
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
}
