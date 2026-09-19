import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transport_route.dart';
import '../data/transport_repository.dart';
import 'route_page_notifier.dart';
import 'transport_pickers.dart';

/// One route with its ordered stops - the state behind the Manage Stops
/// dialog. Stop changes re-fetch the route and refresh the routes list so
/// its stop/student counts stay right.
final routeDetailProvider = AsyncNotifierProvider.autoDispose.family<RouteDetailNotifier, TransportRoute, int>(
  RouteDetailNotifier.new,
);

class RouteDetailNotifier extends AsyncNotifier<TransportRoute> {
  RouteDetailNotifier(this.routeId);

  final int routeId;

  @override
  Future<TransportRoute> build() => ref.read(transportRepositoryProvider).getRoute(routeId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(transportRepositoryProvider).getRoute(routeId));
  }

  Future<void> addStop({
    required String name,
    required int sequenceNumber,
    String? pickupTime,
    String? dropTime,
    String? latitude,
    String? longitude,
  }) async {
    await ref
        .read(transportRepositoryProvider)
        .createStop(
          routeId,
          name: name,
          sequenceNumber: sequenceNumber,
          pickupTime: pickupTime,
          dropTime: dropTime,
          latitude: latitude,
          longitude: longitude,
        );
    await _afterStopChange();
  }

  // Named editStop(), not update() - AsyncNotifier already declares update(cb).
  Future<void> editStop(
    TransportStop stop, {
    String? name,
    int? sequenceNumber,
    String? pickupTime,
    String? dropTime,
    String? latitude,
    String? longitude,
  }) async {
    await ref
        .read(transportRepositoryProvider)
        .updateStop(
          stop.id,
          name: name,
          sequenceNumber: sequenceNumber,
          pickupTime: pickupTime,
          dropTime: dropTime,
          latitude: latitude,
          longitude: longitude,
        );
    await _afterStopChange();
  }

  Future<void> deleteStop(TransportStop stop) async {
    await ref.read(transportRepositoryProvider).deleteStop(stop.id);
    await _afterStopChange();
  }

  Future<void> _afterStopChange() async {
    await refresh();
    ref.invalidate(routePageNotifierProvider);
    ref.invalidate(routeStopsProvider(routeId));
  }
}
