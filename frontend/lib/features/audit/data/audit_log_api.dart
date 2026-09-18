import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/audit_entry.dart';

final auditLogApiProvider = Provider<AuditLogApi>((ref) => AuditLogApi(ref.watch(dioClientProvider)));

class AuditLogApi {
  AuditLogApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<AuditEntry>> list({
    int? schoolId,
    String? module,
    String? from,
    String? to,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/audit-logs',
      queryParameters: {..._filters(schoolId, module, from, to), 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, AuditEntry.fromJson);
  }

  /// The whole filtered trail as CSV bytes, fetched through the authenticated
  /// client rather than by opening a URL - a token does not belong in a link.
  Future<List<int>> downloadCsv({int? schoolId, String? module, String? from, String? to}) async {
    final response = await _dio.get<List<int>>(
      '/audit-logs',
      queryParameters: {..._filters(schoolId, module, from, to), 'format': 'csv'},
      options: Options(responseType: ResponseType.bytes),
    );

    return response.data ?? const [];
  }

  Map<String, dynamic> _filters(int? schoolId, String? module, String? from, String? to) {
    return {'school_id': ?schoolId, 'module': ?module, 'from': ?from, 'to': ?to};
  }
}
