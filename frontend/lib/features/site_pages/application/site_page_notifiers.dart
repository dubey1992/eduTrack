import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/site_page.dart';
import '../data/site_page_repository.dart';

/// A page as visitors read it. Fails with [SitePageRepository.notFoundCode]
/// for a page that does not exist or is not published.
///
/// No automatic retry, here or below: "not available" is an answer, not a
/// blip. Riverpod's default retry asked the live server six times in
/// eighteen seconds for an unpublished page and kept a spinner up the whole
/// time. A real failure offers its own Try again.
final publishedSitePageProvider = FutureProvider.autoDispose.family<SitePage, String>(
  (ref, slug) => ref.read(sitePageRepositoryProvider).fetchPublished(slug),
  retry: (retryCount, error) => null,
);

/// One page as the editor opens it.
final sitePageDetailProvider = FutureProvider.autoDispose.family<SitePageDetail, String>(
  (ref, slug) => ref.read(sitePageRepositoryProvider).get(slug),
  retry: (retryCount, error) => null,
);

final sitePageListNotifierProvider = AsyncNotifierProvider<SitePageListNotifier, List<SitePageSummary>>(
  SitePageListNotifier.new,
  retry: (retryCount, error) => null,
);

/// The Super Admin's list of website pages, and every change made to them.
///
/// Changes go through here rather than straight to the repository so the
/// list is read again after each one: the editor sits on top of the list,
/// and going back to it should never show a page's old status.
///
/// A failed change throws to whoever asked, which is a form that can say
/// what was wrong; only a failed load puts the list into its error state.
class SitePageListNotifier extends AsyncNotifier<List<SitePageSummary>> {
  SitePageRepository get _repository => ref.read(sitePageRepositoryProvider);

  @override
  Future<List<SitePageSummary>> build() => _repository.list();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.list);
  }

  Future<SitePageDetail> create({
    required String slug,
    required String title,
    required String body,
    SitePageKind kind = SitePageKind.page,
    PageDetails details = const PageDetails(),
  }) async {
    final page = await _repository.create(slug: slug, title: title, body: body, kind: kind, details: details);
    await _refresh();

    return page;
  }

  Future<SitePageDetail> save(
    String slug, {
    required String newSlug,
    required String title,
    required String body,
    PageDetails details = const PageDetails(),
  }) async {
    final page = await _repository.save(slug, newSlug: newSlug, title: title, body: body, details: details);
    await _refresh();

    // A rename takes the page off its old address at once.
    if (newSlug != slug) ref.invalidate(publishedSitePageProvider(slug));

    return page;
  }

  Future<SitePageDetail> publish(String slug) async {
    final page = await _repository.publish(slug);
    await _refresh();

    // The Super Admin is about to open the page to check their work, and
    // this app may still be holding what it said before.
    ref.invalidate(publishedSitePageProvider(slug));

    return page;
  }

  Future<SitePageDetail> uploadCover(String slug, {required List<int> bytes, required String fileName}) async {
    final page = await _repository.uploadCover(slug, bytes: bytes, fileName: fileName);
    await _refresh();

    return page;
  }

  Future<SitePageDetail> removeCover(String slug) async {
    final page = await _repository.removeCover(slug);
    await _refresh();

    return page;
  }

  Future<void> delete(String slug) async {
    await _repository.delete(slug);
    ref.invalidate(publishedSitePageProvider(slug));
    await _refresh();
  }

  /// Reads the list again without flashing it back to a spinner. A list
  /// that cannot be read keeps what it had: the change itself went through,
  /// and saying otherwise would be wrong.
  Future<void> _refresh() async {
    final fresh = await AsyncValue.guard(_repository.list);
    if (fresh.hasValue) state = fresh;
  }
}
