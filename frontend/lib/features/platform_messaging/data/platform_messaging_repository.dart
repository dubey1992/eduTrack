import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/platform_messaging.dart';
import 'platform_messaging_api.dart';

final platformMessagingRepositoryProvider = Provider<PlatformMessagingRepository>(
  (ref) => PlatformMessagingRepository(ref.watch(platformMessagingApiProvider)),
);

/// Turns transport failures into the app's [Failure], so the screen shows
/// the server's own message (and its field errors) rather than an exception.
class PlatformMessagingRepository {
  PlatformMessagingRepository(this._api);

  final PlatformMessagingApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PlatformMessaging> get() => _call(_api.get);

  /// [credentials] holds only the keys to change: a key left out keeps the
  /// stored value, an empty string clears it.
  Future<PlatformMessaging> save({required String provider, required Map<String, String> credentials}) {
    return _call(() => _api.save(provider: provider, credentials: credentials));
  }

  Future<MessagingTestResult> sendTest({required MessagingChannel channel, required String to}) {
    return _call(() => _api.sendTest(channel: channel, to: to));
  }

  Future<PlatformMessaging> saveTemplate({
    required String event,
    required String templateName,
    required String language,
    required List<String> parameters,
  }) {
    return _call(
      () => _api.saveTemplate(event: event, templateName: templateName, language: language, parameters: parameters),
    );
  }

  Future<PlatformMessaging> clearTemplate(String event) => _call(() => _api.clearTemplate(event));
}
