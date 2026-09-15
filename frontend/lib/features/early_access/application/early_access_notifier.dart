import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/early_access_repository.dart';
import '../data/models/early_access_request.dart';

final earlyAccessNotifierProvider = AsyncNotifierProvider<EarlyAccessNotifier, PagedList<EarlyAccessRequest>>(
  EarlyAccessNotifier.new,
);

/// The Super Admin's queue of schools asking to be let in.
class EarlyAccessNotifier extends AsyncNotifier<PagedList<EarlyAccessRequest>> {
  EarlyAccessStatus? _status;
  String _query = '';
  int _page = 1;
  int _perPage = 20;

  EarlyAccessStatus? get status => _status;

  @override
  Future<PagedList<EarlyAccessRequest>> build() => _fetch();

  Future<PagedList<EarlyAccessRequest>> _fetch() async {
    final response = await ref
        .read(earlyAccessRepositoryProvider)
        .list(status: _status?.apiValue, query: _query, page: _page, perPage: _perPage);

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

  Future<void> setStatus(EarlyAccessStatus? status) async {
    _status = status;
    _page = 1;
    await refresh();
  }

  Future<void> search(String query) async {
    _query = query;
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

  /// Moves a request along, and puts the answer straight back into the list
  /// so the row updates without a round trip.
  Future<void> review(EarlyAccessRequest request, {String? status, String? notes}) async {
    final updated = await ref.read(earlyAccessRepositoryProvider).review(request.id, status: status, notes: notes);

    final current = state.value;
    if (current == null) return;

    state = AsyncData(current.withItems([for (final row in current.items) row.id == updated.id ? updated : row]));
  }
}
