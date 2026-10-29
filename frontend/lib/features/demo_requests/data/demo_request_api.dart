import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/demo_request.dart';

final demoRequestApiProvider = Provider<DemoRequestApi>((ref) => DemoRequestApi(ref.watch(dioClientProvider)));

class DemoRequestApi {
  DemoRequestApi(this._dio);

  final Dio _dio;

  /// The marketing page's "Request a Demo" form. Needs no session - it is
  /// written by a school that has no account yet.
  Future<String> submit(Map<String, dynamic> payload) async {
    final response = await _dio.post('/demo-requests', data: payload);

    return response.data['message'] as String? ?? 'Thanks - we will be in touch to confirm your demo.';
  }

  Future<PaginatedResponse<DemoRequest>> list({String? status, String? query, int page = 1, int perPage = 20}) async {
    final response = await _dio.get('/demo-requests', queryParameters: _filters(status, query, page, perPage));

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, DemoRequest.fromJson);
  }

  Future<DemoRequest> review(int id, {String? status, String? notes}) async {
    final response = await _dio.patch('/demo-requests/$id', data: _review(status, notes));

    return DemoRequest.fromJson(response.data as Map<String, dynamic>);
  }

  /// Built a key at a time, as the early access API does: only what was
  /// actually chosen goes on the query string.
  Map<String, dynamic> _filters(String? status, String? query, int page, int perPage) {
    final filters = <String, dynamic>{'page': page, 'per_page': perPage};

    if (status != null) filters['status'] = status;
    if (query != null && query.isNotEmpty) filters['q'] = query;

    return filters;
  }

  Map<String, dynamic> _review(String? status, String? notes) {
    final data = <String, dynamic>{};

    if (status != null) data['status'] = status;
    if (notes != null) data['notes'] = notes;

    return data;
  }
}
