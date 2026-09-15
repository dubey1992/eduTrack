import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'early_access_api.dart';
import 'models/early_access_request.dart';

final earlyAccessRepositoryProvider = Provider<EarlyAccessRepository>(
  (ref) => EarlyAccessRepository(ref.watch(earlyAccessApiProvider)),
);

class EarlyAccessRepository {
  EarlyAccessRepository(this._api);

  final EarlyAccessApi _api;

  Future<String> submit(Map<String, dynamic> payload) async {
    try {
      return await _api.submit(payload);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<EarlyAccessRequest>> list({
    String? status,
    String? query,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      return await _api.list(status: status, query: query, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<EarlyAccessRequest> review(int id, {String? status, String? notes}) async {
    try {
      return await _api.review(id, status: status, notes: notes);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
