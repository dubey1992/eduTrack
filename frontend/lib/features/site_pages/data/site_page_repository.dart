import 'dart:typed_data';

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

  /// Every page. Not paginated: the server holds a few hundred at most.
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

  /// A new page, blog post or help article, saved as a draft. Nobody can
  /// read it until it is published.
  Future<SitePageDetail> create({
    required String slug,
    required String title,
    required String body,
    SitePageKind kind = SitePageKind.page,
    PageDetails details = const PageDetails(),
  }) {
    return _call(() async {
      final response = await _dio.post(
        '/site-pages',
        data: {'slug': slug, 'title': title, 'body': body, 'kind': kind.apiValue, ...details.toJson()},
      );
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Saves the draft. A different [newSlug] moves the page to that address
  /// at once - unlike the words, an address is not drafted.
  Future<SitePageDetail> save(
    String slug, {
    required String newSlug,
    required String title,
    required String body,
    PageDetails details = const PageDetails(),
  }) {
    return _call(() async {
      final response = await _dio.put(
        '/site-pages/$slug',
        data: {'slug': newSlug, 'title': title, 'body': body, ...details.toJson()},
      );
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// A blog post's new cover image. Checked and re-saved by the server, and
  /// a draft like the text: visitors see it once the post is published.
  Future<SitePageDetail> uploadCover(String slug, {required List<int> bytes, required String fileName}) {
    return _call(() async {
      final response = await _dio.post(
        '/site-pages/$slug/cover',
        data: FormData.fromMap({'cover': MultipartFile.fromBytes(bytes, filename: fileName)}),
      );
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<SitePageDetail> removeCover(String slug) {
    return _call(() async {
      final response = await _dio.delete('/site-pages/$slug/cover');
      return SitePageDetail.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// The draft cover's bytes, for the editor's preview; null when there is
  /// none. Fetched through the API, signed in, because drafts are private.
  Future<Uint8List?> coverBytes(String slug) async {
    try {
      final response = await _dio.get<List<int>>(
        '/site-pages/$slug/cover',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw failureFromDioException(e);
    }
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

/// The details a blog post or help article carries beyond its words. Each
/// field left null is left out, so a plain page sends none of them.
class PageDetails {
  const PageDetails({this.summary, this.author, this.topic});

  final String? summary;
  final String? author;
  final String? topic;

  Map<String, String> toJson() => {'summary': ?summary, 'author': ?author, 'topic': ?topic};
}
