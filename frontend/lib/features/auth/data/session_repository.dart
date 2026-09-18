import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/signed_in_session.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) => SessionRepository(ref.watch(dioClientProvider)));

/// Where the signed-in person is signed in, and signing devices out
/// (Phase 21, docs/security.md).
class SessionRepository {
  SessionRepository(this._dio);

  final Dio _dio;

  Future<List<SignedInSession>> list() => _call(() async {
    final response = await _dio.get('/auth/sessions');
    final rows = (response.data as Map<String, dynamic>)['data'] as List<dynamic>;

    return rows.cast<Map<String, dynamic>>().map(SignedInSession.fromJson).toList(growable: false);
  });

  Future<void> signOut(int sessionId) => _call(() => _dio.delete('/auth/sessions/$sessionId'));

  /// Every session but this one. Returns how many ended.
  Future<int> signOutOthers() => _call(() async {
    final response = await _dio.post('/auth/sessions/others');

    return (response.data as Map<String, dynamic>)['ended'] as int? ?? 0;
  });

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
