import 'package:flutter/widgets.dart';

import 'navigation_session.dart';

NavigationSession createNavigationSession() => const NoNavigationSession();

/// There is no Navigation SDK for the web, and no reason to want one: the
/// portal is read at a desk, and the only person who needs turn-by-turn is
/// holding the phone on the bus.
class NoNavigationSession implements NavigationSession {
  const NoNavigationSession();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<NavigationOutcome> guideTo({
    required double latitude,
    required double longitude,
    required String stopName,
  }) async => NavigationOutcome.unavailable;

  @override
  Future<void> stop() async {}

  @override
  Widget view() => const SizedBox.shrink();
}
