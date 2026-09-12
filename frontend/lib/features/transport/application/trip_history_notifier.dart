import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/transport_trip.dart';
import '../data/transport_repository.dart';

final tripHistoryNotifierProvider = AsyncNotifierProvider<TripHistoryNotifier, PagedList<TransportTrip>>(
  TripHistoryNotifier.new,
);

/// Past and current trips, newest first, optionally narrowed to one route.
class TripHistoryNotifier extends AsyncNotifier<PagedList<TransportTrip>> {
  int? _schoolId;
  int? _routeId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<TransportTrip>> build() => _fetch();

  Future<PagedList<TransportTrip>> _fetch() async {
    final response = await ref
        .read(transportRepositoryProvider)
        .listTrips(schoolId: _schoolId, routeId: _routeId, page: _page, perPage: _perPage);
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

  Future<void> setFilters({int? schoolId, int? routeId}) async {
    _schoolId = schoolId;
    _routeId = routeId;
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
}

/// A finished trip's full detail, for the history "View" dialog.
final tripDetailProvider = FutureProvider.autoDispose.family<TransportTrip, int>((ref, tripId) {
  return ref.watch(transportRepositoryProvider).getTrip(tripId);
});
