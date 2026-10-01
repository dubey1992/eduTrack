import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/marketing_draft.dart';

final marketingDraftRepositoryProvider = Provider<MarketingDraftRepository>(
  (ref) => MarketingDraftRepository(ref.watch(dioClientProvider)),
);

/// The Super Admin's side of the homepage (docs/marketing-content.md).
///
/// Unlike the public [MarketingContentRepository], this one throws. The
/// editor has somebody sitting in front of it who needs to know their
/// save did not land, and which box the server objected to.
class MarketingDraftRepository {
  MarketingDraftRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<MarketingDraft> get() {
    return _call(() async {
      final response = await _dio.get('/marketing-content/draft');
      return MarketingDraft.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// [document] is the whole form, not a patch: a key left out of it was
  /// cleared on purpose, and the page goes back to the copy it ships with.
  ///
  /// Values are words, or lists of items for the repeating parts - the two
  /// live in one document because they are published as one.
  Future<MarketingDraft> save(Map<String, Object> document) {
    return _call(() async {
      final response = await _dio.put('/marketing-content/draft', data: {'document': document});
      return MarketingDraft.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<void> publish() {
    return _call(() => _dio.post('/marketing-content/publish'));
  }
}
