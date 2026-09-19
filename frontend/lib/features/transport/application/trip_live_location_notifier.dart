import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/trip_live_location.dart';
import '../data/transport_repository.dart';

/// Where a running trip's bus is, re-read every [TripLiveLocationNotifier.pollInterval]
/// while something is watching it.
///
/// Polling stops by itself once the trip is no longer in progress, and when
/// nothing watches the provider any more (autoDispose cancels the timer).
/// Riverpod's own retry is switched off: this notifier already asks again on
/// its own schedule, and two retry loops would double the requests.
final tripLiveLocationProvider = AsyncNotifierProvider.autoDispose
    .family<TripLiveLocationNotifier, TripLiveLocation, int>(
      TripLiveLocationNotifier.new,
      retry: (retryCount, error) => null,
    );

class TripLiveLocationNotifier extends AsyncNotifier<TripLiveLocation> {
  TripLiveLocationNotifier(this.tripId);

  final int tripId;

  static const pollInterval = Duration(seconds: 15);

  Timer? _timer;

  @override
  Future<TripLiveLocation> build() {
    ref.onDispose(_stopPolling);
    return _load();
  }

  /// Asks again straight away - the error state's Retry button.
  Future<void> refresh() async {
    _stopPolling();
    state = const AsyncLoading();
    await _poll();
  }

  Future<TripLiveLocation> _load() async {
    try {
      final live = await ref.read(transportRepositoryProvider).liveLocation(tripId);
      if (ref.mounted) {
        // A finished trip's bus is not going anywhere worth watching.
        live.isInProgress ? _scheduleNextPoll() : _stopPolling();
      }
      return live;
    } catch (_) {
      // A dropped connection on the office wifi should heal itself without
      // anyone pressing Retry, so a failure keeps the schedule going.
      if (ref.mounted) _scheduleNextPoll();
      rethrow;
    }
  }

  Future<void> _poll() async {
    final result = await AsyncValue.guard(_load);
    if (ref.mounted) state = result;
  }

  void _scheduleNextPoll() {
    _timer?.cancel();
    _timer = Timer(pollInterval, _poll);
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}
