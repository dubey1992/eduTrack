import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../communication/data/communication_api.dart';
import '../../communication/data/models/message.dart';

final myInboxRepositoryProvider = Provider<MyInboxRepository>(
  (ref) => MyInboxRepository(ref.watch(communicationApiProvider)),
);

/// The person's own in-app messages, for the School365ai app's inbox
/// (docs/teacher-app.md, T4). Every call is pinned to the signed-in person
/// on the server; there is no school or person to name.
class MyInboxRepository {
  MyInboxRepository(this._api);

  final CommunicationApi _api;

  Future<PaginatedResponse<Message>> inbox({
    required bool unreadOnly,
    required int page,
    required int perPage,
    String? dateFrom,
    String? dateTo,
  }) =>
      _call(() => _api.inbox(unreadOnly: unreadOnly, page: page, perPage: perPage, dateFrom: dateFrom, dateTo: dateTo));

  Future<int> unreadCount() => _call(_api.unreadCount);

  Future<Message> markRead(int messageId) => _call(() => _api.markRead(messageId));

  Future<int> markAllRead() => _call(_api.markAllRead);

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
