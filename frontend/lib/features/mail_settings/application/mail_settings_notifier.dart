import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mail_settings_repository.dart';
import '../data/models/mail_settings.dart';

final mailSettingsNotifierProvider = AsyncNotifierProvider<MailSettingsNotifier, MailSettings>(
  MailSettingsNotifier.new,
);

/// The platform's SMTP settings, as the Email Settings screen sees them.
///
/// A failed save or test leaves the loaded settings in place and lets the
/// error through to the form, which knows which field to point at; only a
/// failed load puts the whole screen into its error state.
class MailSettingsNotifier extends AsyncNotifier<MailSettings> {
  @override
  Future<MailSettings> build() => ref.read(mailSettingsRepositoryProvider).get();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(mailSettingsRepositoryProvider).get());
  }

  /// [password] null keeps the stored password; an empty string clears it.
  Future<void> save({
    required bool isActive,
    required String host,
    required int port,
    required MailEncryption encryption,
    String? username,
    String? password,
    required String fromAddress,
    required String fromName,
  }) async {
    final saved = await ref
        .read(mailSettingsRepositoryProvider)
        .save(
          isActive: isActive,
          host: host,
          port: port,
          encryption: encryption,
          username: username,
          password: password,
          fromAddress: fromAddress,
          fromName: fromName,
        );

    state = AsyncData(saved);
  }

  /// Sends a test email to [to] and returns the server's message. The
  /// settings come back with the test's time and outcome recorded on them.
  Future<String> sendTest(String to) async {
    final result = await ref.read(mailSettingsRepositoryProvider).sendTest(to: to);
    state = AsyncData(result.settings);
    return result.message;
  }
}
