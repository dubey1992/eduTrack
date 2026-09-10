import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/transport_status.dart';
import '../data/models/vehicle.dart';
import '../data/transport_repository.dart';
import 'transport_pickers.dart';

final vehiclePageNotifierProvider = AsyncNotifierProvider<VehiclePageNotifier, PagedList<Vehicle>>(
  VehiclePageNotifier.new,
);

class VehiclePageNotifier extends AsyncNotifier<PagedList<Vehicle>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Vehicle>> build() => _fetch();

  Future<PagedList<Vehicle>> _fetch() async {
    final response = await ref
        .read(transportRepositoryProvider)
        .listVehicles(schoolId: _schoolId, page: _page, perPage: _perPage);
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

  Future<void> createVehicle({
    int? schoolId,
    required String name,
    required String registrationNumber,
    required int capacity,
  }) async {
    await ref
        .read(transportRepositoryProvider)
        .createVehicle(schoolId: schoolId, name: name, registrationNumber: registrationNumber, capacity: capacity);
    _page = 1;
    await refresh();
    ref.invalidate(vehiclePickerProvider);
  }

  Future<void> updateVehicle(
    Vehicle vehicle, {
    String? name,
    String? registrationNumber,
    int? capacity,
    TransportStatus? status,
  }) async {
    final updated = await ref
        .read(transportRepositoryProvider)
        .updateVehicle(
          vehicle.id,
          name: name,
          registrationNumber: registrationNumber,
          capacity: capacity,
          status: status,
        );
    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(vehiclePickerProvider);
  }

  Future<void> deleteVehicle(Vehicle vehicle) async {
    await ref.read(transportRepositoryProvider).deleteVehicle(vehicle.id);
    await refresh();
    ref.invalidate(vehiclePickerProvider);
  }
}
