/// A parsed Laravel paginated response: { data: [...], meta: { current_page,
/// last_page, total, per_page, ... } }. Shared across every paginated list
/// endpoint (backend CLAUDE.md rule 20 - lists are always paginated).
class PaginatedResponse<T> {
  const PaginatedResponse({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  factory PaginatedResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJson) {
    final items = (json['data'] as List).cast<Map<String, dynamic>>().map(fromJson).toList();
    final meta = json['meta'] as Map<String, dynamic>;

    return PaginatedResponse(
      items: items,
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
      perPage: meta['per_page'] as int,
    );
  }

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;
}
