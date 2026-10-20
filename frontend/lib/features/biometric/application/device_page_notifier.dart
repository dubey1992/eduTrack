import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/biometric_repository.dart';
import '../data/models/biometric_device.dart';

final devicePageNotifierProvider = AsyncNotifierProvider<DevicePageNotifier, PagedList<BiometricDevice>>(
  DevicePageNotifier.new,
);

/// The fingerprint readers a school has (docs/biometric.md, B1).
class DevicePageNotifier extends AsyncNotifier<PagedList<BiometricDevice>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;
  String _q = '';

  String get search => _q;

  @override
  Future<PagedList<BiometricDevice>> build() => _fetch();

  Future<PagedList<BiometricDevice>> _fetch() async {
    final response = await ref
        .read(biometricRepositoryProvider)
        .listDevices(schoolId: _schoolId, page: _page, perPage: _perPage, q: _q.isEmpty ? null : _q);

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

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  /// Back to page one, always: narrowing while sitting on page four asks
  /// for a page that may no longer exist.
  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setSearch(String term) async {
    _q = term.trim();
    _page = 1;
    await refresh();
  }

  Future<void> createDevice({
    int? schoolId,
    required String name,
    required String serialNumber,
    String? location,
  }) async {
    await ref
        .read(biometricRepositoryProvider)
        .createDevice(schoolId: schoolId, name: name, serialNumber: serialNumber, location: location);
    await refresh();
  }

  // Named editDevice(), not update() - AsyncNotifier already declares one.
  Future<void> editDevice(BiometricDevice device, {String? name, String? serialNumber, String? location}) async {
    await ref
        .read(biometricRepositoryProvider)
        .updateDevice(device.id, name: name, serialNumber: serialNumber, location: location);
    await refresh();
  }

  Future<void> removeDevice(BiometricDevice device) async {
    await ref.read(biometricRepositoryProvider).deleteDevice(device.id);
    await refresh();
  }
}
