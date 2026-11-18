import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/geo.dart';
import '../data/location_source.dart';
import '../data/models/location_point.dart';
import '../data/my_trip_repository.dart';
import '../data/trip_service.dart';
import '../data/trip_health_log.dart';
import '../data/trip_offline_store.dart';
import 'leftover_points.dart';

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
/// taken and sent in batches; with no signal the points wait on the phone and
/// go with the next batch. It stops when the switch is turned off, the screen
/// is left (this provider is disposed), the trip ends, or the server says the
/// trip is no longer running.
///
/// A point is kept when the bus has moved [movedEnoughMetres], or when
/// [heartbeat] has passed without one. A bus spends a good part of its run
/// standing still - at a stop, at a gate, in a jam - and four identical
/// positions a minute cost a battery without telling the office anything it
/// did not already know (docs/driver-app.md, D4.2).
class LocationSharingNotifier extends Notifier<LocationSharingState> {
  LocationSharingNotifier(this.tripId);

  final int tripId;

  /// The closest together two positions are ever asked for.
  static const interval = Duration(seconds: 15);

  /// Far enough to be somewhere else: about a bus length and a half, which
  /// is movement rather than a GPS fix wandering while parked.
  static const movedEnoughMetres = 50.0;

  /// A standing bus still says where it is this often, so the office's map
  /// can tell "parked at the gate" from "this phone has stopped talking".
  static const heartbeat = Duration(minutes: 1);

  static const maxBatch = 100;

  /// Hours of a run even at the fastest cadence - a phone that has been out
  /// of signal longer than that keeps the most recent.
  static const maxBuffered = 1000;

  static const deniedMessage = 'Location permission was not given, so your location is not being shared.';
  static const blockedMessage =
      'Location is blocked for this app. Allow it in the phone settings to share your location.';
  static const serviceOffMessage = 'Location is turned off on this phone. Turn it on to share your location.';
  static const unsupportedMessage = 'This device cannot share its location.';
  static const tripEndedMessage = 'The trip is no longer running, so location sharing has stopped.';

  /// The trips whose sharing is on in this app right now - their points are
  /// this notifier's to send, not [LeftoverPoints]'s.
  static final Set<int> sharingNow = {};

  StreamSubscription<DevicePosition>? _positions;
  Timer? _timer;
  late TripService _service;
  late TripHealthLog _log;
  bool _busy = false;
  List<LocationPoint> _buffer = [];

  /// The last position actually kept - what "has it moved?" is measured
  /// against.
  DevicePosition? _lastKept;

  @override
  LocationSharingState build() {
    // Held rather than read later: a provider cannot be read from inside
    // onDispose, and _turnOff runs after this notifier is gone.
    _service = ref.read(tripServiceProvider);
    _log = ref.read(tripHealthLogProvider);
    final leftovers = ref.read(leftoverPointsProvider);

    ref.onDispose(() {
      sharingNow.remove(tripId);
      unawaited(_positions?.cancel());
      _timer?.cancel();
      // Leaving the screen ends the following, so it ends the notification.
      unawaited(_service.stop());
      // The trip ended or the screen was left with points still on the
      // phone: one more try, and My Trip tries again when it next opens.
      unawaited(leftovers.send());
    });
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
    sharingNow.add(tripId);
    state = const LocationSharingState(enabled: true);
    unawaited(_log.add(TripHealthKind.sharingOn, tripId: tripId, count: _buffer.length));

    // The platform decides when the bus has moved; this only decides what
    // is worth keeping. Between the two, a parked bus wakes nothing.
    unawaited(_positions?.cancel());
    _positions = ref
        .read(locationSourceProvider)
        .positions(interval: interval, distanceFilterMetres: movedEnoughMetres)
        .listen(
          _offered,
          onError: (Object error) {
            if (error is LocationUnavailable) _turnOff(message: _messageFor(error.access));
          },
        );

    // Nothing arrives from a standing bus, so the heartbeat asks.
    _armHeartbeat();

    // Android stops a backgrounded app's timers, and a driver's phone sits
    // in a cradle with the screen off for most of a run. Without this the
    // bus vanishes from the office's map a minute after the run starts
    // (docs/driver-app.md, D4).
    await _service.start(title: 'Trip in progress', body: "Sharing this bus's position with the school.");

    // One position straight away. The stream's first delivery can be a
    // while coming, and the office should see the bus the moment the
    // driver switches sharing on, not a minute later.
    await _beat();
  }

  void _turnOff({String? message}) {
    sharingNow.remove(tripId);
    unawaited(_log.add(TripHealthKind.sharingOff, tripId: tripId, detail: message ?? 'Switched off'));
    unawaited(_positions?.cancel());
    _positions = null;
    _timer?.cancel();
    _timer = null;
    _lastKept = null;
    // Stopped whenever sharing is: the notification says the bus is being
    // followed, so it must not outlive the following.
    unawaited(_service.stop());
    if (ref.mounted) state = LocationSharingState(message: message);
  }

  /// A position the platform offered. Kept only if it says something new.
  Future<void> _offered(DevicePosition position) async {
    if (!_worthKeeping(position)) return;

    await _keep(position);
  }

  /// Runs [heartbeat] after the last point was kept, not every [heartbeat]
  /// regardless: a bus that is moving re-arms it with each point and never
  /// reaches it, and only a standing one does.
  void _armHeartbeat() {
    _timer?.cancel();
    _timer = Timer(heartbeat, _beat);
  }

  /// A minute with nothing kept, which is what a standing bus looks like.
  /// Take a real fix rather than re-stamping the last one: the office reads
  /// this as "where the bus is now", and it has to be true.
  Future<void> _beat() async {
    if (_busy || !ref.mounted || !state.enabled) return;

    try {
      await _keep(await ref.read(locationSourceProvider).currentPosition());
    } on LocationUnavailable catch (e) {
      _turnOff(message: _messageFor(e.access));
    }
  }

  /// Far enough from the last kept position to be somewhere else.
  bool _worthKeeping(DevicePosition position) {
    final last = _lastKept;
    if (last == null) return true;

    return metresBetween(last.latitude, last.longitude, position.latitude, position.longitude) >= movedEnoughMetres;
  }

  /// Buffers one position and sends whatever is waiting.
  Future<void> _keep(DevicePosition position) async {
    if (_busy || !ref.mounted || !state.enabled) return;
    _busy = true;

    try {
      _lastKept = position;
      _armHeartbeat();
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
      unawaited(_log.add(TripHealthKind.point, tripId: tripId, count: position.accuracy.round()));

      await _send();
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
        final upload = await repository.sendLocations(tripId, batch);
        _buffer.removeRange(0, batch.length);
        unawaited(_log.add(TripHealthKind.sent, tripId: tripId, count: batch.length));

        // Ended elsewhere - by the office, or the other crew member. What
        // was taken before the end is in; the rest goes with the next
        // batch, and sharing stops.
        if (!upload.inProgress) {
          if (_buffer.isNotEmpty) continue;
          _turnOff(message: tripEndedMessage);
          break;
        }
      } on Failure catch (failure) {
        if (failure.isOffline) {
          unawaited(_log.add(TripHealthKind.waiting, tripId: tripId, count: _buffer.length));
          break;
        }

        // Nothing in the batch was from before the end, or the trip was
        // cancelled: none of it can ever be taken.
        if (failure.code == 'TRIP_NOT_IN_PROGRESS') {
          unawaited(_log.add(TripHealthKind.cleared, tripId: tripId, count: _buffer.length));
          _buffer.clear();
          _turnOff(message: tripEndedMessage);
          break;
        }

        // Points the server will not take are not worth sending again.
        debugPrint('Location batch refused: ${failure.code}');
        unawaited(_log.add(TripHealthKind.refused, tripId: tripId, count: batch.length, detail: failure.code));
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
