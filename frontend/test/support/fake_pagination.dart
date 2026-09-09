import 'package:edutrack_app/core/network/paginated_response.dart';

/// Slices [all] the way the real backend's `paginate()` would, for fake
/// repositories that need to genuinely page (not just record the last call)
/// so notifier tests can assert on real page contents/counts.
PaginatedResponse<T> paginateFake<T>(List<T> all, {required int page, required int perPage}) {
  final start = (page - 1) * perPage;
  final end = (start + perPage).clamp(start, all.length);
  final items = start >= all.length ? <T>[] : all.sublist(start, end);

  return PaginatedResponse(
    items: items,
    currentPage: page,
    lastPage: all.isEmpty ? 1 : (all.length / perPage).ceil(),
    total: all.length,
    perPage: perPage,
  );
}
