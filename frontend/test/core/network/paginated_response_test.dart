import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses items and full pagination metadata from a Laravel response', () {
    final json = {
      'data': [
        {'id': 1, 'name': 'Sunrise School'},
        {'id': 2, 'name': 'Green Valley School'},
      ],
      'meta': {'current_page': 2, 'last_page': 5, 'total': 42, 'per_page': 10},
    };

    final response = PaginatedResponse.fromJson(json, (item) => item['name'] as String);

    expect(response.items, ['Sunrise School', 'Green Valley School']);
    expect(response.currentPage, 2);
    expect(response.lastPage, 5);
    expect(response.total, 42);
    expect(response.perPage, 10);
  });
}
