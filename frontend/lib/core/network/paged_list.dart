/// One page of items plus the metadata needed to render pagination controls
/// - wraps a list notifier's state so mutations (create/update/delete) can
/// still update items in place without losing where the user is paged to.
class PagedList<T> {
  const PagedList({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  const PagedList.empty() : items = const [], currentPage = 1, lastPage = 1, total = 0, perPage = 20;

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  PagedList<T> withItems(List<T> items) {
    return PagedList(items: items, currentPage: currentPage, lastPage: lastPage, total: total, perPage: perPage);
  }
}
