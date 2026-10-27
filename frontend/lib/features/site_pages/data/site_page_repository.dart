import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/site_page.dart';

final sitePageRepositoryProvider = Provider<SitePageRepository>(
  (ref) => SitePageRepository(ref.watch(dioClientProvider)),
);

/// Website pages: About Us, Privacy Policy, Terms of Use and whatever else
/// the Super Admin adds (docs/site-pages.md).
///
/// [fetchPublished] is the visitor's side and needs no session; everything
/// else is the Super Admin's.
class SitePageRepository {
  SitePageRepository(this._dio);

  /// The code the server answers with for a page that does not exist, has
  /// been deleted, or has never been published.
  static const notFoundCode = 'PAGE_NOT_FOUND';

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SitePage> fetchPublished(String slug) {
    return _call(() async {
      final response = await _dio.get('/pages/$slug');
      return SitePage.fromJson((response.data as Map<String, dynamic>)['page'] as Map<String, dynamic>);
    });
  }

  /// Every page. Not paginated: the server holds at most fifty.
  Future<List<SitePageSummary>> list() {
    return _call(() async {
      final response = await _dio.get('/site-pages');
      final rows = (response.data as Map<String, dynamic>)['data'] as List;
      return [for (final row in rows) SitePageSummary.fromJson(row as Map<String, dynamic>)];
    });
  }

  Future<SitePageDetail> get(String slug) {
    return _call(() async {
      final response = await _dio.get('/site-pages/$slug');
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// A new page, saved as a draft. Nobody can read it until it is published.
  Future<SitePageDetail> create({required String slug, required String title, required String body}) {
    return _call(() async {
      final response = await _dio.post('/site-pages', data: {'slug': slug, 'title': title, 'body': body});
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Saves the draft. A different [newSlug] moves the page to that address
  /// at once - unlike the words, an address is not drafted.
  Future<SitePageDetail> save(String slug, {required String newSlug, required String title, required String body}) {
    return _call(() async {
      final response = await _dio.put('/site-pages/$slug', data: {'slug': newSlug, 'title': title, 'body': body});
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<SitePageDetail> publish(String slug) {
    return _call(() async {
      final response = await _dio.post('/site-pages/$slug/publish');
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<void> delete(String slug) {
    return _call(() => _dio.delete('/site-pages/$slug'));
  }
}
