import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/driver.dart';
import '../data/models/transport_status.dart';
import '../data/transport_repository.dart';
import 'transport_pickers.dart';

final driverPageNotifierProvider = AsyncNotifierProvider<DriverPageNotifier, PagedList<Driver>>(DriverPageNotifier.new);

class DriverPageNotifier extends AsyncNotifier<PagedList<Driver>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Driver>> build() => _fetch();

  Future<PagedList<Driver>> _fetch() async {
    final response = await ref
        .read(transportRepositoryProvider)
        .listDrivers(schoolId: _schoolId, page: _page, perPage: _perPage);
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

  Future<void> createDriver({
    int? schoolId,
    required String name,
    String? mobile,
    required String licenceNumber,
    String? licenceExpiry,
  }) async {
    await ref
        .read(transportRepositoryProvider)
        .createDriver(
          schoolId: schoolId,
          name: name,
          mobile: mobile,
          licenceNumber: licenceNumber,
          licenceExpiry: licenceExpiry,
        );
    _page = 1;
    await refresh();
    ref.invalidate(driverPickerProvider);
  }

  Future<void> updateDriver(
    Driver driver, {
    String? name,
    String? mobile,
    String? licenceNumber,
    String? licenceExpiry,
    TransportStatus? status,
  }) async {
    final updated = await ref
        .read(transportRepositoryProvider)
        .updateDriver(
          driver.id,
          name: name,
          mobile: mobile,
          licenceNumber: licenceNumber,
          licenceExpiry: licenceExpiry,
          status: status,
        );
    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(driverPickerProvider);
  }

  Future<void> deleteDriver(Driver driver) async {
    await ref.read(transportRepositoryProvider).deleteDriver(driver.id);
    await refresh();
    ref.invalidate(driverPickerProvider);
  }
}
