import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/early_access_request.dart';

final earlyAccessApiProvider = Provider<EarlyAccessApi>((ref) => EarlyAccessApi(ref.watch(dioClientProvider)));

class EarlyAccessApi {
  EarlyAccessApi(this._dio);

  final Dio _dio;

  /// The marketing page's form. The only write in the app that needs no
  /// session - it is how a school with no account asks for one.
  Future<String> submit(Map<String, dynamic> payload) async {
    final response = await _dio.post('/early-access', data: payload);

    return response.data['message'] as String? ?? 'Thanks - we have your details.';
  }

  Future<PaginatedResponse<EarlyAccessRequest>> list({
    String? status,
    String? query,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _dio.get('/early-access', queryParameters: _filters(status, query, page, perPage));

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, EarlyAccessRequest.fromJson);
  }

  Future<EarlyAccessRequest> review(int id, {String? status, String? notes}) async {
    final response = await _dio.patch('/early-access/$id', data: _review(status, notes));

    return EarlyAccessRequest.fromJson(response.data as Map<String, dynamic>);
  }

  /// Built a key at a time rather than with collection-ifs: the analyzer
  /// wants the null-aware marker for a conditional entry, and rejects it on a
  /// non-nullable key. One of the two has to give, and this reads fine.
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
