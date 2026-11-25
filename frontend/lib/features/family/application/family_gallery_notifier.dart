import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gallery/data/gallery_models.dart';
import '../data/family_repository.dart';

/// The events with photos a parent sees, newest first (docs/mobile-apps-review.md,
/// M12, 8.6), a page at a time.
class FamilyGallery {
  const FamilyGallery({required this.events, required this.page, required this.hasMore, this.loadingMore = false});

  final List<GalleryEvent> events;
  final int page;
  final bool hasMore;
  final bool loadingMore;

  GalleryEvent? byId(int id) => events.where((event) => event.id == id).firstOrNull;
}

final familyGalleryProvider = AsyncNotifierProvider.autoDispose<FamilyGalleryNotifier, FamilyGallery>(
  FamilyGalleryNotifier.new,
  retry: (retryCount, error) => null,
);

class FamilyGalleryNotifier extends AsyncNotifier<FamilyGallery> {
  @override
  Future<FamilyGallery> build() async {
    final first = await ref.read(familyRepositoryProvider).gallery();
    return FamilyGallery(events: first.items, page: 1, hasMore: first.currentPage < first.lastPage);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// The next, older page. A failure leaves what is shown and is rethrown.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(FamilyGallery(events: current.events, page: current.page, hasMore: true, loadingMore: true));
    try {
      final next = await ref.read(familyRepositoryProvider).gallery(page: current.page + 1);
      state = AsyncData(
        FamilyGallery(
          events: [...current.events, ...next.items],
          page: next.currentPage,
          hasMore: next.currentPage < next.lastPage,
        ),
      );
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}
