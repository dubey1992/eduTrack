import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/transport_route.dart';
import '../data/models/transport_status.dart';
import '../data/transport_repository.dart';
import 'driver_page_notifier.dart';
import 'transport_pickers.dart';
import 'vehicle_page_notifier.dart';

final routePageNotifierProvider = AsyncNotifierProvider<RoutePageNotifier, PagedList<TransportRoute>>(
  RoutePageNotifier.new,
);

class RoutePageNotifier extends AsyncNotifier<PagedList<TransportRoute>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<TransportRoute>> build() => _fetch();

  Future<PagedList<TransportRoute>> _fetch() async {
    final response = await ref
        .read(transportRepositoryProvider)
        .listRoutes(schoolId: _schoolId, page: _page, perPage: _perPage);
    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  Future<void> createRoute({int? schoolId, required String name, int? vehicleId, int? driverId}) async {
    await ref
        .read(transportRepositoryProvider)
        .createRoute(schoolId: schoolId, name: name, vehicleId: vehicleId, driverId: driverId);
    _page = 1;
    await refresh();
    _invalidatePickers();
  }

  Future<void> updateRoute(
    TransportRoute route, {
    String? name,
    required int? vehicleId,
    required int? driverId,
    TransportStatus? status,
  }) async {
    final updated = await ref
        .read(transportRepositoryProvider)
        .updateRoute(route.id, name: name, vehicleId: vehicleId, driverId: driverId, status: status);
    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    _invalidatePickers();
  }

  Future<void> deleteRoute(TransportRoute route) async {
    await ref.read(transportRepositoryProvider).deleteRoute(route.id);
    await refresh();
    _invalidatePickers();
  }

  // A route change moves vehicles/drivers in or out of service, which the
  // Vehicles/Drivers lists show as a "Route" column and the pickers use to
  // hide taken ones - all of them are stale now.
  void _invalidatePickers() {
    ref.invalidate(routePickerProvider);
    ref.invalidate(vehiclePickerProvider);
    ref.invalidate(driverPickerProvider);
    ref.invalidate(vehiclePageNotifierProvider);
    ref.invalidate(driverPageNotifierProvider);
  }
}
