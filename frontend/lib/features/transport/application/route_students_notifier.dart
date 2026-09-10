import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/transport_route.dart';
import '../data/transport_repository.dart';

/// The riders of one route, paged - the "Students on Bus" list.
final routeStudentsProvider = AsyncNotifierProvider.autoDispose
    .family<RouteStudentsNotifier, PagedList<RouteStudent>, int>(RouteStudentsNotifier.new);

class RouteStudentsNotifier extends AsyncNotifier<PagedList<RouteStudent>> {
  RouteStudentsNotifier(this.routeId);

  final int routeId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<RouteStudent>> build() => _fetch();

  Future<PagedList<RouteStudent>> _fetch() async {
    final response = await ref
        .read(transportRepositoryProvider)
        .listRouteStudents(routeId, page: _page, perPage: _perPage);
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
}
