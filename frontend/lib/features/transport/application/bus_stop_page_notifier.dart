import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  String? schoolName;

  /// Where the school is, for a map to centre on and a stop to be measured
  /// against. Null when there is no single school, or nobody has placed it.
  LatLng? get schoolAt {
    final latitude = double.tryParse(schoolLatitude ?? '');
    final longitude = double.tryParse(schoolLongitude ?? '');

    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  int? get schoolId => _schoolId;

  @override
  Future<PagedList<BusStop>> build() => _fetch();

  Future<PagedList<BusStop>> _fetch() async {
    final answer = await ref
        .read(transportRepositoryProvider)
        .listBusStops(schoolId: _schoolId, status: _status, q: _q.isEmpty ? null : _q, page: _page, perPage: _perPage);

    schoolLatitude = answer.schoolLatitude;
    schoolLongitude = answer.schoolLongitude;
    schoolName = answer.schoolName;

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

  /// Returns what was made, because the route builder adds a place and
  /// puts it on the route in one action (docs/maps.md).
  Future<BusStop> addStop({
    int? schoolId,
    required String name,
    required String latitude,
    required String longitude,
    String? landmark,
  }) async {
    final made = await ref
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

    return made;
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
