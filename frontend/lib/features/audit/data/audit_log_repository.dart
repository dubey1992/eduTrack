import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'audit_log_api.dart';
import 'models/audit_entry.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>(
  (ref) => AuditLogRepository(ref.watch(auditLogApiProvider)),
);

/// Turns transport failures into the app's [Failure], so the screen shows
/// the server's own message rather than an exception.
class AuditLogRepository {
  AuditLogRepository(this._api);

  final AuditLogApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<AuditEntry>> list({
    int? schoolId,
    String? module,
    String? from,
    String? to,
    required int page,
    required int perPage,
  }) {
    return _call(() => _api.list(schoolId: schoolId, module: module, from: from, to: to, page: page, perPage: perPage));
  }

  Future<List<int>> downloadCsv({int? schoolId, String? module, String? from, String? to}) {
    return _call(() => _api.downloadCsv(schoolId: schoolId, module: module, from: from, to: to));
  }
}
