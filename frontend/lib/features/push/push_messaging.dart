import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A notification as the app needs it: what it says, and where a tap goes.
class PushNotice {
  const PushNotice({required this.title, required this.body, required this.route});

  final String title;
  final String body;

  /// One of the app's own addresses - `/leave`, `/teaching`, `/inbox`.
  final String route;
}

/// Push notifications, behind an interface (docs/teacher-app.md, T6), so the
/// app runs - and its tests run - with no Firebase at all.
abstract class PushMessaging {
  /// Starts push and asks the person's permission. False when push is not
  /// set up in this build, or the person said no.
  Future<bool> start();

  /// This install's address for push, or null.
  Future<String?> token();

  /// A new address, when Firebase rotates it.
  Stream<String> get tokenRefreshes;

  /// A notification tapped while the app was in the background.
  Stream<PushNotice> get opened;

  /// The notification that opened the app from closed, if one did.
  Future<PushNotice?> launchedBy();

  /// A notification that arrived while the app was open on screen.
  Stream<PushNotice> get received;
}

/// No push in this build: the Firebase keys were not given.
class NoPush implements PushMessaging {
  const NoPush();

  @override
  Future<bool> start() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushNotice> get opened => const Stream.empty();

  @override
  Future<PushNotice?> launchedBy() async => null;

  @override
  Stream<PushNotice> get received => const Stream.empty();
}

/// Firebase Cloud Messaging. Configured from `--dart-define`s at build time
/// rather than a google-services.json in the repository, so the business's
/// Firebase project never enters git and a build without the keys simply has
/// no push.
class FirebasePush implements PushMessaging {
  FirebasePush(this._options);

  final FirebaseOptions _options;
  bool _started = false;

  /// The keys from the build, or null when any is missing.
  static FirebaseOptions? optionsFromEnvironment() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

    if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty || projectId.isEmpty) return null;

    return const FirebaseOptions(apiKey: apiKey, appId: appId, messagingSenderId: senderId, projectId: projectId);
  }

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> start() async {
    try {
      if (!_started) {
        if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: _options);
        _started = true;
      }
      final permission = await _messaging.requestPermission();
      return permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error) {
      // A phone without Google Play services, or a misconfigured project:
      // the app works on without push.
      debugPrint('Push could not start: $error');
      return false;
    }
  }

  @override
  Future<String?> token() async {
    if (!_started) return null;
    try {
      // The classic registration token, which the server sends to through
      // FCM HTTP v1's `token` target. firebase_messaging 17 deprecates it in
      // favour of an installation id for a newer direct-send route; moving
      // means changing the server's target too, so both move together.
      // ignore: deprecated_member_use
      return await _messaging.getToken();
    } catch (error) {
      debugPrint('No push token: $error');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes =>
      // See token(): the registration token and its refreshes move together.
      // ignore: deprecated_member_use
      _started ? _messaging.onTokenRefresh : const Stream.empty();

  @override
  Stream<PushNotice> get opened => _started ? FirebaseMessaging.onMessageOpenedApp.map(_notice) : const Stream.empty();

  @override
  Future<PushNotice?> launchedBy() async {
    if (!_started) return null;
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _notice(message);
  }

  @override
  Stream<PushNotice> get received => _started ? FirebaseMessaging.onMessage.map(_notice) : const Stream.empty();

  static PushNotice _notice(RemoteMessage message) => PushNotice(
    title: message.notification?.title ?? 'School365ai',
    body: message.notification?.body ?? '',
    route: message.data['route'] as String? ?? '/inbox',
  );
}

final pushMessagingProvider = Provider<PushMessaging>((ref) {
  final options = FirebasePush.optionsFromEnvironment();
  return options == null ? const NoPush() : FirebasePush(options);
});
