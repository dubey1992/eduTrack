import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'mail_settings_api.dart';
import 'models/mail_settings.dart';

final mailSettingsRepositoryProvider = Provider<MailSettingsRepository>(
  (ref) => MailSettingsRepository(ref.watch(mailSettingsApiProvider)),
);

/// Turns transport failures into the app's [Failure], so the screen shows
/// the server's own message (and its field errors) rather than an exception.
class MailSettingsRepository {
  MailSettingsRepository(this._api);

  final MailSettingsApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<MailSettings> get() => _call(_api.get);

  /// [password] null keeps the stored password; an empty string clears it.
  Future<MailSettings> save({
    required bool isActive,
    required String host,
    required int port,
    required MailEncryption encryption,
    String? username,
    String? password,
    required String fromAddress,
    required String fromName,
  }) {
    return _call(
      () => _api.save(
        isActive: isActive,
        host: host,
        port: port,
        encryption: encryption,
        username: username,
        password: password,
        fromAddress: fromAddress,
        fromName: fromName,
      ),
    );
  }

  Future<MailTestResult> sendTest({required String to}) => _call(() => _api.sendTest(to: to));
}
