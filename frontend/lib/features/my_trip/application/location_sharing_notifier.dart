import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../data/location_source.dart';
import '../data/models/location_point.dart';
import '../data/my_trip_repository.dart';
import '../data/trip_offline_store.dart';

class LocationSharingState {
  const LocationSharingState({this.enabled = false, this.starting = false, this.message});

  /// Positions are being taken and sent.
  final bool enabled;

  /// Waiting on the permission question.
  final bool starting;

  /// Why sharing is off when the attendant wanted it on - shown under the switch.
  final String? message;
}

final locationSharingProvider = NotifierProvider.autoDispose.family<LocationSharingNotifier, LocationSharingState, int>(
  LocationSharingNotifier.new,
);

/// "Share my location" on a running trip (docs/maps.md, M3).
///
/// While it is on and the My Trip screen is open, the phone's position is
/// taken every [interval] and sent in batches; with no signal the points wait
/// on the phone and go with the next batch. It stops when the switch is
/// turned off, the screen is left (this provider is disposed), the trip ends,
/// or the server says the trip is no longer running.
class LocationSharingNotifier extends Notifier<LocationSharingState> {
  LocationSharingNotifier(this.tripId);

  final int tripId;

  static const interval = Duration(seconds: 15);
  static const maxBatch = 100;

  /// About four hours at one point every 15 seconds - a phone that has been
  /// out of signal longer than that keeps the most recent.
  static const maxBuffered = 1000;

  static const deniedMessage = 'Location permission was not given, so your location is not being shared.';
  static const blockedMessage =
      'Location is blocked for this app. Allow it in the phone settings to share your location.';
  static const serviceOffMessage = 'Location is turned off on this phone. Turn it on to share your location.';
  static const unsupportedMessage = 'This device cannot share its location.';
  static const tripEndedMessage = 'The trip is no longer running, so location sharing has stopped.';

  Timer? _timer;
  bool _busy = false;
  List<LocationPoint> _buffer = [];

  @override
  LocationSharingState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_startIfWanted);
    return const LocationSharingState();
  }

  /// On by default on a running trip, unless the attendant switched it off.
  Future<void> _startIfWanted() async {
    if (!ref.mounted) return;
    final wanted = await ref.read(tripOfflineStoreProvider).readShareLocation() ?? true;
    if (wanted && ref.mounted) await _turnOn();
  }

  /// The switch. The choice is remembered for the next trip.
  Future<void> setEnabled(bool enabled) async {
    await ref.read(tripOfflineStoreProvider).saveShareLocation(enabled);
    if (!ref.mounted) return;

    if (enabled) {
      await _turnOn();
    } else {
      _turnOff();
    }
  }

  Future<void> _turnOn() async {
    if (state.enabled || state.starting) return;
    state = const LocationSharingState(starting: true);

    final access = await ref.read(locationSourceProvider).requestAccess();
    if (!ref.mounted) return;

    if (access != LocationAccess.granted) {
      _turnOff(message: _messageFor(access));
      return;
    }

    final stored = await ref.read(tripOfflineStoreProvider).readPoints();
    if (!ref.mounted) return;

    _buffer = [...stored.where((p) => p.tripId == tripId), ..._buffer];
    state = const LocationSharingState(enabled: true);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    await _tick();
  }

  void _turnOff({String? message}) {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = LocationSharingState(message: message);
  }

  /// Takes one position and sends whatever is waiting.
  Future<void> _tick() async {
    if (_busy || !ref.mounted || !state.enabled) return;
    _busy = true;

    try {
      final position = await ref.read(locationSourceProvider).currentPosition();
      _buffer.add(
        LocationPoint(
          tripId: tripId,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
          recordedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      if (_buffer.length > maxBuffered) _buffer = _buffer.sublist(_buffer.length - maxBuffered);

      await _send();
    } on LocationUnavailable catch (e) {
      _turnOff(message: _messageFor(e.access));
    } finally {
      _busy = false;
    }
  }

  Future<void> _send() async {
    // Read up front: the screen may be left while a request is in flight.
    final repository = ref.read(myTripRepositoryProvider);
    final store = ref.read(tripOfflineStoreProvider);

    while (_buffer.isNotEmpty && ref.mounted && state.enabled) {
      final batch = _buffer.take(maxBatch).toList();
      try {
        await repository.sendLocations(tripId, batch);
        _buffer.removeRange(0, batch.length);
      } on Failure catch (failure) {
        if (failure.isOffline) break;

        if (failure.code == 'TRIP_NOT_IN_PROGRESS') {
          _buffer.clear();
          _turnOff(message: tripEndedMessage);
          break;
        }

        // Points the server will not take are not worth sending again.
        debugPrint('Location batch refused: ${failure.code}');
        _buffer.removeRange(0, batch.length);
      }
    }

    await _persist(store);
  }

  /// Keeps this trip's unsent points on the phone beside any other trip's.
  Future<void> _persist(TripOfflineStore store) async {
    final others = (await store.readPoints()).where((p) => p.tripId != tripId);
    await store.savePoints([...others, ..._buffer]);
  }

  String _messageFor(LocationAccess access) => switch (access) {
    LocationAccess.granted => '',
    LocationAccess.denied => deniedMessage,
    LocationAccess.deniedForever => blockedMessage,
    LocationAccess.serviceOff => serviceOffMessage,
    LocationAccess.unsupported => unsupportedMessage,
  };
}
