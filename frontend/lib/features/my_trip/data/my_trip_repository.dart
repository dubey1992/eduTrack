import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import '../../transport/data/models/transport_trip.dart';
import 'models/location_point.dart';
import 'models/my_route.dart';
import 'models/not_sent_mark.dart';
import 'models/trip_mark.dart';
import 'my_trip_api.dart';
import 'offline_start.dart';
import 'trip_offline_store.dart';

final myTripRepositoryProvider = Provider<MyTripRepository>(
  (ref) => MyTripRepository(ref.watch(myTripApiProvider), ref.watch(tripOfflineStoreProvider)),
);

/// Failures that mean "no signal, try again later" rather than "no".
extension OfflineFailure on Failure {
  bool get isOffline => code == 'NETWORK_ERROR';
}

/// The server's answer to a batch of marks: one result per mark, and the trip
/// as it now stands.
class SyncOutcome {
  const SyncOutcome({required this.results, required this.trip});

  final List<MarkResult> results;
  final TransportTrip trip;
}

/// The attendant's routes and trips, from the API when it can be reached and
/// from the phone's last copy when it cannot.
class MyTripRepository {
  MyTripRepository(this._api, this._store);

  final MyTripApi _api;
  final TripOfflineStore _store;

  /// Today's routes. With no signal, the copy last fetched - marked as such.
  /// A trip started on this phone that the answer does not have yet is laid
  /// over it, so its route offers Continue rather than Start (2.4).
  Future<MyRoutesDay> myRoutes() async {
    Map<String, dynamic> json;
    var fromCache = false;
    try {
      json = await _guard(_api.myRoutes);
      await _store.saveRoutes(json);
    } on Failure catch (failure) {
      final cached = failure.isOffline ? await _store.readRoutes() : null;
      if (cached == null) rethrow;
      json = cached;
      fromCache = true;
    }
    return MyRoutesDay.fromJson(await _withPhoneStarts(json), fromCache: fromCache);
  }

  Future<Map<String, dynamic>> _withPhoneStarts(Map<String, dynamic> json) async {
    final starts = await _store.readPendingStarts();
    if (starts.isEmpty) return json;

    final routes = [
      for (final route in ((json['routes'] as List?) ?? const []).cast<Map<String, dynamic>>())
        await _withPhoneStart(route, starts),
    ];
    return {...json, 'routes': routes};
  }

  Future<Map<String, dynamic>> _withPhoneStart(Map<String, dynamic> route, List<PendingStart> starts) async {
    final today = Map<String, dynamic>.of((route['today'] as Map<String, dynamic>?) ?? const {});
    for (final start in starts.where((s) => s.routeId == route['id'])) {
      final trip = await _store.readTrip(start.localId);
      if (today[start.direction.apiValue] == null && trip != null) today[start.direction.apiValue] = trip;
    }
    return {...route, 'today': today};
  }

  /// The server's id for [tripId]: itself for a real trip, the real one a
  /// stand-in was mapped to, or null while its start is still waiting.
  Future<int?> serverIdFor(int tripId) async {
    if (!isLocalTrip(tripId)) return tripId;
    return (await _store.readRealIds())[tripId];
  }

  Future<List<PendingStart>> pendingStarts() => _store.readPendingStarts();

  /// Starts on the server a trip started on this phone, with the moment
  /// Start was pressed; maps the stand-in to the real trip. Throws the
  /// server's refusal - and "no signal", to try again later.
  Future<int> startOnServer(PendingStart start) async {
    final json = await _guard(
      () => _api.startTrip(routeId: start.routeId, direction: start.direction, startedAt: start.startedAt),
    );
    final trip = tripFromJson(json);
    await _store.saveTrip(trip.id, json);
    await settleStart(start, realId: trip.id);
    return trip.id;
  }

  /// The trip already running on [start]'s route and direction - started by
  /// the other crew member meanwhile - or null.
  Future<int?> runningTripFor(PendingStart start) async {
    final routes = await myRoutes();
    final route = routes.routes.where((r) => r.id == start.routeId).firstOrNull;
    final trip = route?.tripFor(start.direction);
    return trip != null && !isLocalTrip(trip.id) && trip.isInProgress ? trip.id : null;
  }

  /// Takes [start] off the waiting list; [realId] is the trip it became, or
  /// null when the server would not start it.
  Future<void> settleStart(PendingStart start, {int? realId}) async {
    final starts = await _store.readPendingStarts();
    await _store.savePendingStarts([
      for (final s in starts)
        if (s.localId != start.localId) s,
    ]);
    if (realId != null) await _store.saveRealIds({...await _store.readRealIds(), start.localId: realId});
  }

  /// One trip in full. With no signal, the copy last fetched. A trip
  /// started on this phone is the server's once it has it, and the phone's
  /// own until then.
  Future<(TransportTrip, {bool fromCache})> trip(int tripId) async {
    if (isLocalTrip(tripId)) {
      final real = await serverIdFor(tripId);
      if (real != null) return trip(real);
      final saved = await _store.readTrip(tripId);
      if (saved == null) throw Failure.network();
      return (tripFromJson(saved), fromCache: true);
    }
    try {
      final json = await _guard(() => _api.trip(tripId));
      await _store.saveTrip(tripId, json);
      return (tripFromJson(json), fromCache: false);
    } on Failure catch (failure) {
      final cached = failure.isOffline ? await _store.readTrip(tripId) : null;
      if (cached == null) rethrow;
      return (tripFromJson(cached), fromCache: true);
    }
  }

  /// Starts today's trip. With no signal it starts on the phone instead,
  /// from the route's roster on the phone's copy of My routes (2.4), and
  /// waits to be started on the server; without a roster saved there is
  /// nothing to run it from, and "no signal" stands.
  Future<TransportTrip> startTrip({required int routeId, required TripDirection direction}) async {
    try {
      final json = await _guard(() => _api.startTrip(routeId: routeId, direction: direction));
      final trip = tripFromJson(json);
      await _store.saveTrip(trip.id, json);
      return trip;
    } on Failure catch (failure) {
      if (!failure.isOffline) rethrow;
      final onPhone = await _startOnPhone(routeId, direction);
      if (onPhone == null) rethrow;
      return onPhone;
    }
  }

  Future<TransportTrip?> _startOnPhone(int routeId, TripDirection direction) async {
    final routes = await _store.readRoutes();
    final route = ((routes?['routes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((r) => r['id'] == routeId)
        .firstOrNull;
    if (routes == null || route == null || route['roster'] == null) return null;

    final start = PendingStart(
      localId: localTripId(routeId, direction),
      routeId: routeId,
      direction: direction,
      startedAt: DateTime.now().toUtc().toIso8601String(),
    );
    final json = localTripJson(route: route, date: routes['date'] as String, direction: direction, start: start);

    // A stand-in reused from another day starts clean.
    final realIds = await _store.readRealIds()
      ..remove(start.localId);
    await _store.saveRealIds(realIds);
    await _store.saveTrip(start.localId, json);
    await _store.savePendingStarts([
      for (final s in await _store.readPendingStarts())
        if (s.localId != start.localId) s,
      start,
    ]);
    return tripFromJson(json);
  }

  Future<SyncOutcome> sync(int tripId, List<TripMark> marks) async {
    final json = await _guard(() => _api.sync(tripId, marks));
    final tripJson = json['trip'] as Map<String, dynamic>;
    await _store.saveTrip(tripId, tripJson);

    return SyncOutcome(
      results: (json['results'] as List).cast<Map<String, dynamic>>().map(MarkResult.fromJson).toList(),
      trip: tripFromJson(tripJson),
    );
  }

  /// How many points the server kept, and whether the trip is still
  /// running. A finished trip still takes points from before its end
  /// (docs/mobile-apps-review.md, 2.3); a server too old to say is taken as
  /// "still running", which is what it would have refused otherwise.
  Future<({int accepted, bool inProgress})> sendLocations(int tripId, List<LocationPoint> points) async {
    final json = await _guard(() => _api.sendLocations(tripId, points));
    return (accepted: json['accepted'] as int? ?? 0, inProgress: json['in_progress'] as bool? ?? true);
  }

  /// No answer at all, or a server fault, is "offline": worth trying again.
  /// Anything else is the server's considered answer and is passed on as is.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (e.response == null || (status != null && status >= 500)) throw Failure.network();
      throw failureFromDioException(e);
    }
  }
}
