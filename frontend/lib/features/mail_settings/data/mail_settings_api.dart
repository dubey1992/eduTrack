import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/mail_settings.dart';

final mailSettingsApiProvider = Provider<MailSettingsApi>((ref) => MailSettingsApi(ref.watch(dioClientProvider)));

class MailSettingsApi {
  MailSettingsApi(this._dio);

  final Dio _dio;

  Future<MailSettings> get() async {
    final response = await _dio.get('/settings/mail');
    return MailSettings.fromJson(response.data as Map<String, dynamic>);
  }

  /// [password] null leaves the key out, which keeps the stored password;
  /// an empty string clears it.
  Future<MailSettings> save({
    required bool isActive,
    required String host,
    required int port,
    required MailEncryption encryption,
    String? username,
    String? password,
    required String fromAddress,
    required String fromName,
  }) async {
    final response = await _dio.put(
      '/settings/mail',
      data: {
        'is_active': isActive,
        'host': host,
        'port': port,
        'encryption': encryption.apiValue,
        'username': username,
        'password': ?password,
        'from_address': fromAddress,
        'from_name': fromName,
      },
    );

    return MailSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MailTestResult> sendTest({required String to}) async {
    final response = await _dio.post('/settings/mail/test', data: {'to': to});
    return MailTestResult.fromJson(response.data as Map<String, dynamic>);
  }
}
