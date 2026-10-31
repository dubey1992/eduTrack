import 'dart:async';
import 'dart:typed_data';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/site_pages/data/models/site_page.dart';
import 'package:edutrack_app/features/site_pages/data/site_page_repository.dart';

/// One page as the fake server holds it.
class FakePage {
  FakePage({
    required this.slug,
    required this.title,
    this.body = '',
    this.builtIn = false,
    this.publishedTitle,
    this.publishedBody,
    this.publishedAt,
    this.kind = SitePageKind.page,
    this.summary,
    this.author,
    this.topic,
    this.hasCover = false,
  });

  final SitePageKind kind;
  String? summary;
  String? author;
  String? topic;
  bool hasCover;

  String slug;
  String title;
  String body;
  final bool builtIn;
  String? publishedTitle;
  String? publishedBody;
  DateTime? publishedAt;

  bool get isLive => publishedBody != null;
  bool get changed => !isLive || publishedTitle != title || publishedBody != body;

  SitePageDetail toDetail() => SitePageDetail(
    slug: slug,
    title: title,
    kind: kind,
    summary: summary,
    author: author,
    topic: topic,
    hasCover: hasCover,
    builtIn: builtIn,
    isLive: isLive,
    hasUnpublishedChanges: changed,
    body: body,
    publishedAt: publishedAt,
    publishedTitle: publishedTitle,
    publishedBody: publishedBody,
  );
}

const _notFound = Failure(code: SitePageRepository.notFoundCode, message: 'This page is not available.');

/// Test double for [SitePageRepository] - keeps the pages the way the server
/// would (draft and published side by side), and records what was asked.
class FakeSitePageRepository implements SitePageRepository {
  FakeSitePageRepository({List<FakePage>? pages}) : pages = pages ?? builtIns();

  /// About and Privacy live, Terms not yet - as the server ships them.
  static List<FakePage> builtIns() => [
    FakePage(
      slug: 'about',
      title: 'About Us',
      body: 'School365ai is school management software.',
      builtIn: true,
      publishedTitle: 'About Us',
      publishedBody: 'School365ai is school management software.',
    ),
    FakePage(
      slug: 'privacy',
      title: 'Privacy Policy',
      body: '## Who can see it\n\nStaff at your own school.',
      builtIn: true,
      publishedTitle: 'Privacy Policy',
      publishedBody: '## Who can see it\n\nStaff at your own school.',
      publishedAt: DateTime(2026, 10, 26),
    ),
    FakePage(slug: 'terms', title: 'Terms of Use', body: '## Your account\n\n[COMPANY LEGAL NAME]', builtIn: true),
  ];

  List<FakePage> pages;

  Failure? failListWith;
  Failure? failPublishedWith;
  Failure? failSaveWith;
  Failure? failDeleteWith;

  /// When set, [fetchPublished] waits on it - so a test can see the loading state.
  Completer<void>? publishedGate;

  int listCalls = 0;
  int fetchPublishedCalls = 0;
  final saves = <({String slug, String newSlug, String title, String body})>[];
  final creates = <({String slug, String title, String body, SitePageKind kind, PageDetails details})>[];
  final detailsSaved = <PageDetails>[];
  final coverUploads = <String>[];
  final coverRemovals = <String>[];

  /// What the cover preview answers; null is "no cover".
  Uint8List? coverPreview;
  Failure? failCoverWith;
  final published = <String>[];
  final deleted = <String>[];

  FakePage? _find(String slug) {
    for (final page in pages) {
      if (page.slug == slug) return page;
    }
    return null;
  }

  @override
  Future<SitePage> fetchPublished(String slug) async {
    fetchPublishedCalls++;
    if (publishedGate != null) await publishedGate!.future;
    if (failPublishedWith != null) throw failPublishedWith!;

    final page = _find(slug);
    if (page == null || !page.isLive) throw _notFound;

    return SitePage(
      slug: page.slug,
      title: page.publishedTitle!,
      body: page.publishedBody!,
      publishedAt: page.publishedAt,
    );
  }

  @override
  Future<List<SitePageSummary>> list() async {
    listCalls++;
    if (failListWith != null) throw failListWith!;

    return [for (final page in pages) page.toDetail()];
  }

  @override
  Future<SitePageDetail> get(String slug) async {
    final page = _find(slug);
    if (page == null) throw const Failure(code: 'NOT_FOUND', message: 'The requested resource was not found.');

    return page.toDetail();
  }

  @override
  Future<SitePageDetail> create({
    required String slug,
    required String title,
    required String body,
    SitePageKind kind = SitePageKind.page,
    PageDetails details = const PageDetails(),
  }) async {
    creates.add((slug: slug, title: title, body: body, kind: kind, details: details));
    if (failSaveWith != null) throw failSaveWith!;

    final page = FakePage(
      slug: slug,
      title: title,
      body: body,
      kind: kind,
      summary: details.summary,
      author: details.author,
      topic: details.topic,
    );
    pages.add(page);

    return page.toDetail();
  }

  @override
  Future<SitePageDetail> save(
    String slug, {
    required String newSlug,
    required String title,
    required String body,
    PageDetails details = const PageDetails(),
  }) async {
    saves.add((slug: slug, newSlug: newSlug, title: title, body: body));
    detailsSaved.add(details);
    if (failSaveWith != null) throw failSaveWith!;

    final page = _find(slug)!
      ..slug = newSlug
      ..title = title
      ..body = body
      ..summary = details.summary ?? _find(slug)!.summary
      ..author = details.author ?? _find(slug)!.author
      ..topic = details.topic ?? _find(slug)!.topic;

    return page.toDetail();
  }

  @override
  Future<SitePageDetail> publish(String slug) async {
    published.add(slug);

    final page = _find(slug)!
      ..publishedTitle = _find(slug)!.title
      ..publishedBody = _find(slug)!.body
      ..publishedAt = DateTime(2026, 10, 27, 9);

    return page.toDetail();
  }

  @override
  Future<void> delete(String slug) async {
    deleted.add(slug);
    if (failDeleteWith != null) throw failDeleteWith!;

    pages.removeWhere((page) => page.slug == slug);
  }

  @override
  Future<SitePageDetail> uploadCover(String slug, {required List<int> bytes, required String fileName}) async {
    coverUploads.add(slug);
    if (failCoverWith != null) throw failCoverWith!;

    final page = _find(slug)!..hasCover = true;
    coverPreview = Uint8List.fromList(bytes);

    return page.toDetail();
  }

  @override
  Future<SitePageDetail> removeCover(String slug) async {
    coverRemovals.add(slug);

    final page = _find(slug)!..hasCover = false;
    coverPreview = null;

    return page.toDetail();
  }

  @override
  Future<Uint8List?> coverBytes(String slug) async => coverPreview;
}
