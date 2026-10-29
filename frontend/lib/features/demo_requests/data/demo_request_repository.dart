import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'demo_request_api.dart';
import 'models/demo_request.dart';

final demoRequestRepositoryProvider = Provider<DemoRequestRepository>(
  (ref) => DemoRequestRepository(ref.watch(demoRequestApiProvider)),
);

class DemoRequestRepository {
  DemoRequestRepository(this._api);

  final DemoRequestApi _api;

  Future<String> submit(Map<String, dynamic> payload) async {
    try {
      return await _api.submit(payload);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<DemoRequest>> list({String? status, String? query, int page = 1, int perPage = 20}) async {
    try {
      return await _api.list(status: status, query: query, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<DemoRequest> review(int id, {String? status, String? notes}) async {
    try {
      return await _api.review(id, status: status, notes: notes);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
