/// A parsed Laravel paginated response: { data: [...], meta: { current_page,
/// last_page, total, ... } }. Shared across every future paginated list
/// endpoint (backend CLAUDE.md rule 20 - lists are always paginated).
class PaginatedResponse<T> {
  const PaginatedResponse({required this.items, required this.currentPage, required this.lastPage});

  factory PaginatedResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJson) {
    final items = (json['data'] as List).cast<Map<String, dynamic>>().map(fromJson).toList();
    final meta = json['meta'] as Map<String, dynamic>;

    return PaginatedResponse(
      items: items,
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
    );
  }

  final List<T> items;
  final int currentPage;
  final int lastPage;
}
