import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'offline_fee_payment.dart';

final offlineFeesRepositoryProvider = Provider<OfflineFeesRepository>(
  (ref) => OfflineFeesRepository(ref.watch(dioClientProvider)),
);

/// Fees taken offline (docs/offline-web.md, O4): sending one when the line
/// is back, the list, and settling one that could not become a receipt.
class OfflineFeesRepository {
  OfflineFeesRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// What the outbox kept, as it was taken. Safe to send twice: the server
  /// knows the payment by its client id.
  Future<OfflineFeePayment> send(Map<String, dynamic> payload) {
    return _call(() async {
      final response = await _dio.post('/fees/offline-payments', data: payload);
      return OfflineFeePayment.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<PaginatedResponse<OfflineFeePayment>> list({
    OfflineFeeStatus? status,
    int? schoolId,
    int page = 1,
    int perPage = 20,
  }) {
    return _call(() async {
      final response = await _dio.get(
        '/fees/offline-payments',
        queryParameters: {'status': ?status?.wire, 'school_id': ?schoolId, 'page': page, 'per_page': perPage},
      );
      return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, OfflineFeePayment.fromJson);
    });
  }

  /// Keeps the money on the student's account (a receipt now).
  Future<OfflineFeePayment> keepOnAccount(int id, {String? reason}) =>
      _settle(id, {'action': 'credit', 'reason': ?reason});

  /// Records the money handed back to the family.
  Future<OfflineFeePayment> handBack(int id, {required String reason, required String mode, String? reference}) =>
      _settle(id, {'action': 'refund', 'reason': reason, 'refund_mode': mode, 'reference': ?reference});

  Future<OfflineFeePayment> _settle(int id, Map<String, dynamic> body) {
    return _call(() async {
      final response = await _dio.post('/fees/offline-payments/$id/settle', data: body);
      return OfflineFeePayment.fromJson(response.data as Map<String, dynamic>);
    });
  }
}
