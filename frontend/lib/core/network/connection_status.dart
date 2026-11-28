import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_connection.dart';

/// Whether work is kept on this device when the server cannot be reached,
/// and the forms open from kept copies (docs/offline-web.md, O3). On in the
/// web app only: the phone apps have their own offline handling and keep it
/// unchanged. A provider, so tests can switch it on.
final offlineWorkProvider = Provider<bool>((ref) => kIsWeb);

/// Whether the app can reach the server right now (docs/offline-web.md, O1).
///
/// Two witnesses, so neither has to be trusted alone: the browser's own
/// online/offline signal, and every API call - one that cannot reach the
/// server marks the app offline, any answer at all marks it online again.
/// A browser on a network with no route to the internet still says "online";
/// the failed call is what notices.
///
/// Coming back online is announced to [onReconnected] listeners, which send
/// the work saved while offline (O3).
final connectionStatusProvider = NotifierProvider<ConnectionStatus, bool>(ConnectionStatus.new);

class ConnectionStatus extends Notifier<bool> {
  final _reconnected = StreamController<void>.broadcast();

  /// Fires each time the app goes from offline to online.
  Stream<void> get onReconnected => _reconnected.stream;

  @override
  bool build() {
    final subscription = browserConnectionChanges().listen((online) => online ? markOnline() : markOffline());
    ref.onDispose(() {
      subscription.cancel();
      _reconnected.close();
    });
    return browserSaysOnline();
  }

  void markOffline() {
    if (state) state = false;
  }

  void markOnline() {
    if (state) return;
    state = true;
    if (!_reconnected.isClosed) _reconnected.add(null);
  }
}
