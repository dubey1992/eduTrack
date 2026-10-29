import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/platform_messaging.dart';

final platformMessagingApiProvider = Provider<PlatformMessagingApi>(
  (ref) => PlatformMessagingApi(ref.watch(dioClientProvider)),
);

class PlatformMessagingApi {
  PlatformMessagingApi(this._dio);

  final Dio _dio;

  Future<PlatformMessaging> get() async {
    final response = await _dio.get('/platform/messaging');
    return PlatformMessaging.fromJson(response.data as Map<String, dynamic>);
  }

  /// [credentials] holds only the keys to change: a key left out keeps the
  /// stored value, an empty string clears it.
  Future<PlatformMessaging> save({required String provider, required Map<String, String> credentials}) async {
    final response = await _dio.put('/platform/messaging', data: {'provider': provider, 'credentials': credentials});
    return PlatformMessaging.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MessagingTestResult> sendTest({required MessagingChannel channel, required String to}) async {
    final response = await _dio.post('/platform/messaging/test', data: {'channel': channel.apiValue, 'to': to});
    return MessagingTestResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PlatformMessaging> saveTemplate({
    required String event,
    required String templateName,
    required String language,
    required List<String> parameters,
  }) async {
    final response = await _dio.put(
      _templatePath(event),
      data: {'template_name': templateName, 'language': language, 'parameters': parameters},
    );
    return PlatformMessaging.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PlatformMessaging> clearTemplate(String event) async {
    final response = await _dio.delete(_templatePath(event));
    return PlatformMessaging.fromJson(response.data as Map<String, dynamic>);
  }

  String _templatePath(String event) => '/platform/whatsapp-templates/${Uri.encodeComponent(event)}';
}
