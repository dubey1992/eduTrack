import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/promotion_batch.dart';
import '../data/promotion_repository.dart';

/// The promotions a school has already run (docs/promotion.md).
///
/// Read by every role that may see academic set-up, not only the ones that
/// may run a promotion: "what happened to my class last year" is ordinary
/// academic information, and the server says the same.
final promotionHistoryProvider = AsyncNotifierProvider<PromotionHistoryNotifier, PagedList<PromotionBatch>>(
  PromotionHistoryNotifier.new,
);

class PromotionHistoryNotifier extends AsyncNotifier<PagedList<PromotionBatch>> {
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<PromotionBatch>> build() => _fetch();

  Future<PagedList<PromotionBatch>> _fetch() async {
    final response = await ref.read(promotionRepositoryProvider).history(page: _page, perPage: _perPage);

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

  Future<void> setPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }
}
