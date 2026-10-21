import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/bus_stop.dart';
import '../data/transport_repository.dart';

final busStopPageNotifierProvider = AsyncNotifierProvider<BusStopPageNotifier, PagedList<BusStop>>(
  BusStopPageNotifier.new,
);

/// The school's list of bus stops (docs/maps.md).
class BusStopPageNotifier extends AsyncNotifier<PagedList<BusStop>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;
  String _q = '';
  String? _status;

  String? get status => _status;

  /// Where the school is, as the last page reported it. Null when there is
  /// no single school to speak of, or nobody has placed it.
  String? schoolLatitude;
  String? schoolLongitude;

  int? get schoolId => _schoolId;

  @override
  Future<PagedList<BusStop>> build() => _fetch();

  Future<PagedList<BusStop>> _fetch() async {
    final answer = await ref
        .read(transportRepositoryProvider)
        .listBusStops(schoolId: _schoolId, status: _status, q: _q.isEmpty ? null : _q, page: _page, perPage: _perPage);

    schoolLatitude = answer.schoolLatitude;
    schoolLongitude = answer.schoolLongitude;

    final response = answer.page;

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

  Future<void> setSearch(String q) async {
    _q = q.trim();
    _page = 1;
    await refresh();
  }

  Future<void> setStatus(String? status) async {
    _status = status;
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

  Future<void> addStop({
    int? schoolId,
    required String name,
    required String latitude,
    required String longitude,
    String? landmark,
  }) async {
    await ref
        .read(transportRepositoryProvider)
        .createBusStop(
          schoolId: schoolId ?? _schoolId,
          name: name,
          latitude: latitude,
          longitude: longitude,
          landmark: landmark,
        );
    _page = 1;
    await refresh();
  }

  /// Named editStop(), not update() - AsyncNotifier already declares one.
  Future<void> editStop(
    BusStop stop, {
    String? name,
    String? latitude,
    String? longitude,
    String? landmark,
    String? status,
  }) async {
    await ref
        .read(transportRepositoryProvider)
        .updateBusStop(
          stop.id,
          name: name,
          latitude: latitude,
          longitude: longitude,
          landmark: landmark,
          status: status,
        );
    await refresh();
  }

  Future<void> removeStop(BusStop stop) async {
    await ref.read(transportRepositoryProvider).deleteBusStop(stop.id);
    await refresh();
  }
}
