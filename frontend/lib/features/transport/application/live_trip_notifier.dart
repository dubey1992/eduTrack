import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transport_trip.dart';
import '../data/transport_repository.dart';
import 'trip_history_notifier.dart';

class LiveTripParams {
  const LiveTripParams({this.schoolId, required this.routeId});

  final int? schoolId;
  final int routeId;

  @override
  bool operator ==(Object other) => other is LiveTripParams && other.schoolId == schoolId && other.routeId == routeId;

  @override
  int get hashCode => Object.hash(schoolId, routeId);
}

/// The trip currently running on one route - null when there is none. After
/// end/cancel the finished trip stays in state so the screen can show its
/// summary until another one is started.
final liveTripProvider = AsyncNotifierProvider.autoDispose.family<LiveTripNotifier, TransportTrip?, LiveTripParams>(
  LiveTripNotifier.new,
);

class LiveTripNotifier extends AsyncNotifier<TransportTrip?> {
  LiveTripNotifier(this.params);

  final LiveTripParams params;

  @override
  Future<TransportTrip?> build() => _fetch();

  Future<TransportTrip?> _fetch() async {
    final repository = ref.read(transportRepositoryProvider);
    final page = await repository.listTrips(
      schoolId: params.schoolId,
      routeId: params.routeId,
      status: TripStatus.inProgress,
      page: 1,
      perPage: 1,
    );
    if (page.items.isEmpty) return null;
    return repository.getTrip(page.items.first.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> start(TripDirection direction) async {
    final trip = await ref.read(transportRepositoryProvider).startTrip(routeId: params.routeId, direction: direction);
    state = AsyncData(trip);
    ref.invalidate(tripHistoryNotifierProvider);
  }

  Future<void> reachStop(int stopId) async {
    state = AsyncData(await ref.read(transportRepositoryProvider).reachStop(_current.id, stopId));
  }

  Future<void> updateRider(int studentId, TripRiderStatus status) async {
    state = AsyncData(await ref.read(transportRepositoryProvider).updateRider(_current.id, studentId, status));
  }

  Future<void> end() async {
    state = AsyncData(await ref.read(transportRepositoryProvider).endTrip(_current.id));
    ref.invalidate(tripHistoryNotifierProvider);
  }

  Future<void> cancel() async {
    state = AsyncData(await ref.read(transportRepositoryProvider).cancelTrip(_current.id));
    ref.invalidate(tripHistoryNotifierProvider);
  }

  TransportTrip get _current {
    final trip = state.value;
    if (trip == null) throw StateError('No trip is loaded for this route.');
    return trip;
  }
}
