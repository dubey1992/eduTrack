import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/platform_messaging.dart';
import '../data/platform_messaging_repository.dart';

final platformMessagingNotifierProvider = AsyncNotifierProvider<PlatformMessagingNotifier, PlatformMessaging>(
  PlatformMessagingNotifier.new,
);

/// School365ai's SMS and WhatsApp account, as the Messaging screen sees it.
///
/// Every change the server accepts hands the whole account back, which
/// replaces the state. A failed save, test or template change leaves the
/// loaded account in place and lets the error through to the form or dialog
/// that asked; only a failed load puts the whole screen into its error state.
class PlatformMessagingNotifier extends AsyncNotifier<PlatformMessaging> {
  @override
  Future<PlatformMessaging> build() => ref.read(platformMessagingRepositoryProvider).get();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(platformMessagingRepositoryProvider).get());
  }

  /// [credentials] holds only the keys to change: a key left out keeps the
  /// stored value, an empty string clears it.
  Future<void> save({required String provider, required Map<String, String> credentials}) async {
    final saved = await ref
        .read(platformMessagingRepositoryProvider)
        .save(provider: provider, credentials: credentials);
    state = AsyncData(saved);
  }

  /// Sends a test message to [to] and returns the server's message. The
  /// account comes back with the test's time and outcome recorded on it.
  Future<String> sendTest(MessagingChannel channel, String to) async {
    final result = await ref.read(platformMessagingRepositoryProvider).sendTest(channel: channel, to: to);
    state = AsyncData(result.settings);
    return result.message;
  }

  Future<void> saveTemplate({
    required String event,
    required String templateName,
    required String language,
    required List<String> parameters,
  }) async {
    final saved = await ref
        .read(platformMessagingRepositoryProvider)
        .saveTemplate(event: event, templateName: templateName, language: language, parameters: parameters);
    state = AsyncData(saved);
  }

  Future<void> clearTemplate(String event) async {
    final saved = await ref.read(platformMessagingRepositoryProvider).clearTemplate(event);
    state = AsyncData(saved);
  }
}
