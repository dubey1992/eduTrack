import 'dart:async';

import 'package:web/web.dart' as web;

bool browserSaysOnline() => web.window.navigator.onLine;

/// true when the browser goes online, false when it goes offline.
Stream<bool> browserConnectionChanges() {
  final online = web.EventStreamProviders.onlineEvent.forTarget(web.window).map((_) => true);
  final offline = web.EventStreamProviders.offlineEvent.forTarget(web.window).map((_) => false);
  final merged = StreamController<bool>.broadcast();
  final subscriptions = [online.listen(merged.add), offline.listen(merged.add)];
  merged.onCancel = () {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  };
  return merged.stream;
}
