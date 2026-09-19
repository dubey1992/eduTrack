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
  Future<MyRoutesDay> myRoutes() async {
    try {
      final json = await _guard(_api.myRoutes);
      await _store.saveRoutes(json);
      return MyRoutesDay.fromJson(json);
    } on Failure catch (failure) {
      final cached = failure.isOffline ? await _store.readRoutes() : null;
      if (cached == null) rethrow;
      return MyRoutesDay.fromJson(cached, fromCache: true);
    }
  }

  /// One trip in full. With no signal, the copy last fetched.
  Future<(TransportTrip, {bool fromCache})> trip(int tripId) async {
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

  /// Starting a trip needs the server: it is what creates the rider list.
  Future<TransportTrip> startTrip({required int routeId, required TripDirection direction}) async {
    final json = await _guard(() => _api.startTrip(routeId: routeId, direction: direction));
    final trip = tripFromJson(json);
    await _store.saveTrip(trip.id, json);
    return trip;
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

  /// Returns how many points the server kept.
  Future<int> sendLocations(int tripId, List<LocationPoint> points) async {
    final json = await _guard(() => _api.sendLocations(tripId, points));
    return json['accepted'] as int? ?? 0;
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
