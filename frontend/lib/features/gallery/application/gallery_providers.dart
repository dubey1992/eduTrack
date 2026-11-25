import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../../../core/utils/picked_file.dart';
import '../data/gallery_models.dart';
import '../data/gallery_repository.dart';

/// The events this person may see, newest first (M12, 8.6).
final galleryEventsProvider = AsyncNotifierProvider.autoDispose<GalleryEventsNotifier, PaginatedResponse<GalleryEvent>>(
  GalleryEventsNotifier.new,
);

class GalleryEventsNotifier extends AsyncNotifier<PaginatedResponse<GalleryEvent>> {
  @override
  Future<PaginatedResponse<GalleryEvent>> build() => ref.read(galleryRepositoryProvider).list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Creates or changes an event; a [Failure] is rethrown for the form.
  Future<GalleryEvent> save(GalleryEventDraft draft, {int? id}) async {
    final repository = ref.read(galleryRepositoryProvider);
    final saved = id == null ? await repository.create(draft) : await repository.update(id, draft);
    ref.invalidateSelf();
    if (id != null) ref.invalidate(galleryEventProvider(id));
    return saved;
  }
}

/// One event, with its photos.
final galleryEventProvider = AsyncNotifierProvider.autoDispose.family<GalleryEventNotifier, GalleryEvent, int>(
  GalleryEventNotifier.new,
);

class GalleryEventNotifier extends AsyncNotifier<GalleryEvent> {
  GalleryEventNotifier(this.eventId);

  final int eventId;

  @override
  Future<GalleryEvent> build() => ref.read(galleryRepositoryProvider).get(eventId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> addPhoto(PickedFile file) async {
    state = AsyncData(await ref.read(galleryRepositoryProvider).addPhoto(eventId, file));
    ref.invalidate(galleryEventsProvider);
  }

  Future<void> removePhoto(int photoId) async {
    await ref.read(galleryRepositoryProvider).removePhoto(photoId);
    state = await AsyncValue.guard(build);
    ref.invalidate(galleryEventsProvider);
  }

  Future<void> delete() async {
    await ref.read(galleryRepositoryProvider).delete(eventId);
    ref.invalidate(galleryEventsProvider);
  }
}
