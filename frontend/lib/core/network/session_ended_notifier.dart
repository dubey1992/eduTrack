import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the sign-in screens say when the server ended the session.
const sessionEndedMessage = 'Your session has ended. Sign in again.';

/// Whether the server has said the current session is over: signed out from
/// another device, expired, the account switched off, a bus phone revoked
/// (docs/security.md, "The phone apps").
///
/// Set by the Dio interceptor when a request that carried the session comes
/// back 401. Like [maintenanceProvider], it is about every screen at once,
/// not the one somebody happens to be on - without it each screen kept
/// showing its own error until the app was restarted. The auth notifier
/// listens and signs out on this device; the sign-in screens read it to say
/// why somebody is looking at them.
final sessionEndedProvider = NotifierProvider<SessionEndedNotifier, bool>(SessionEndedNotifier.new);

class SessionEndedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void report() {
    if (!state) state = true;
  }

  /// A new session has begun, so the old one's ending is no longer news.
  void clear() {
    if (state) state = false;
  }
}

/// Whether a 401 for this request means the session is over. Not for the
/// sign-in endpoints, where a 401 is a wrong password or passcode, and not
/// for a request that carried no session to end.
bool endsSession({required int? status, required String path, required bool carriedSession}) {
  if (status != 401 || !carriedSession) return false;

  return !path.startsWith('/auth/');
}
