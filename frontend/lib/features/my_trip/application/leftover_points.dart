import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../data/models/location_point.dart';
import '../data/my_trip_repository.dart';
import '../data/trip_health_log.dart';
import '../data/trip_offline_store.dart';
import 'location_sharing_notifier.dart';

final leftoverPointsProvider = Provider<LeftoverPoints>(
  (ref) => LeftoverPoints(
    ref.read(myTripRepositoryProvider),
    ref.read(tripOfflineStoreProvider),
    ref.read(tripHealthLogProvider),
  ),
);

/// GPS points still on the phone for a trip nobody is sharing any more
/// (docs/mobile-apps-review.md, 2.3).
///
/// A bus out of signal on its last stretch keeps its positions on the
/// phone; then the trip ends, sharing stops, and before this nothing ever
/// sent them - the office's map of that run stopped where the signal did.
/// The server takes points from before a trip's end, so they are sent
/// here: when sharing stops and whenever My Trip opens or comes back to the
/// front. A trip that is still sharing is left to its own sender.
class LeftoverPoints {
  LeftoverPoints(this._repository, this._store, this._log);

  final MyTripRepository _repository;
  final TripOfflineStore _store;
  final TripHealthLog _log;

  bool _busy = false;

  Future<void> send() async {
    if (_busy) return;
    _busy = true;

    try {
      final stored = await _store.readPoints();
      final tripIds = {
        for (final point in stored)
          if (!LocationSharingNotifier.sharingNow.contains(point.tripId)) point.tripId,
      };
      // A point is one trip at one instant - re-read from the store it is
      // a new object, so it is matched by that rather than by identity.
      final settled = <String>{};
      String keyOf(LocationPoint point) => '${point.tripId}@${point.recordedAt}';

      for (final tripId in tripIds) {
        final points = stored.where((p) => p.tripId == tripId).toList();
        try {
          final serverId = await _repository.serverIdFor(tripId);
          // Started on this phone and not yet on the server: wait (2.4).
          if (serverId == null) continue;
          for (var start = 0; start < points.length; start += LocationSharingNotifier.maxBatch) {
            final batch = points.skip(start).take(LocationSharingNotifier.maxBatch).toList();
            await _repository.sendLocations(serverId, batch);
            settled.addAll(batch.map(keyOf));
            await _log.add(TripHealthKind.sent, tripId: tripId, count: batch.length);
          }
        } on Failure catch (failure) {
          // No signal yet: they wait for the next try.
          if (failure.isOffline) continue;

          // The server's considered "no" - a cancelled trip, or nothing from
          // before its end. Sending them again cannot change that.
          debugPrint('Leftover positions refused: ${failure.code}');
          final refused = points.where((p) => !settled.contains(keyOf(p))).toList();
          settled.addAll(refused.map(keyOf));
          await _log.add(TripHealthKind.cleared, tripId: tripId, count: refused.length, detail: failure.code);
        }
      }

      if (settled.isEmpty) return;

      // Read again: a trip that started sharing meanwhile may have written.
      final now = await _store.readPoints();
      await _store.savePoints(now.where((p) => !settled.contains(keyOf(p))).toList());
    } finally {
      _busy = false;
    }
  }
}
