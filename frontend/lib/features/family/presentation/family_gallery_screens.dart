import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/signed_in_image.dart';
import '../../gallery/data/gallery_models.dart';
import '../../gallery/presentation/gallery_screens.dart' show PhotoGrid;
import '../application/family_gallery_notifier.dart';
import 'widgets/family_widgets.dart';

/// Events and photos from the school (docs/mobile-apps-review.md, M12, 8.6):
/// the whole school's and the children's classes', newest first.
class FamilyGalleryScreen extends ConsumerWidget {
  const FamilyGalleryScreen({super.key});

  Future<void> _more(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(familyGalleryProvider.notifier).loadMore();
    } on Failure catch (failure) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.familyGallery)),
      body: ref
          .watch(familyGalleryProvider)
          .when(
            loading: () => const PlaceholderCards(),
            error: (error, _) =>
                FamilyErrorView(error: error, onRetry: () => ref.read(familyGalleryProvider.notifier).refresh()),
            data: (gallery) => gallery.events.isEmpty
                ? FamilyEmptyView(
                    icon: Icons.photo_library_rounded,
                    title: l10n.familyNoGallery,
                    message: l10n.familyNoGalleryMessage,
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.read(familyGalleryProvider.notifier).refresh(),
                    child: ListView(
                      key: const Key('family-gallery'),
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final event in gallery.events) ...[_EventCard(event: event), const SizedBox(height: 12)],
                        if (gallery.hasMore)
                          Center(
                            child: OutlinedButton(
                              key: const Key('family-gallery-more'),
                              onPressed: gallery.loadingMore ? null : () => _more(context, ref),
                              child: Text(l10n.familyGalleryOlder),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
    );
  }
}

String _audience(BuildContext context, GalleryEvent event) =>
    event.className == null ? context.l10n.familyGalleryWholeSchool : event.className!;

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final GalleryEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shown = event.photos.take(3).toList();
    final rest = event.photos.length - shown.length;

    return FamilyCard(
      key: Key('family-gallery-${event.id}'),
      onTap: () => context.push('/gallery/${event.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            [event.dateLabel, _audience(context, event), l10n.familyGalleryPhotos(event.photos.length)].join(' · '),
            style: TextStyle(color: context.appColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SignedInImage(url: shown[i].thumbUrl),
                          if (i == shown.length - 1 && rest > 0)
                            ColoredBox(
                              color: Colors.black45,
                              child: Center(
                                child: Text(
                                  '+$rest',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              for (var i = shown.length; i < 3; i++) ...[const SizedBox(width: 6), const Expanded(child: SizedBox())],
            ],
          ),
        ],
      ),
    );
  }
}

/// One event's photos; a tap opens them full screen.
class FamilyGalleryEventScreen extends ConsumerWidget {
  const FamilyGalleryEventScreen({super.key, required this.eventId});

  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final gallery = ref.watch(familyGalleryProvider);
    final event = gallery.value?.byId(eventId);

    return Scaffold(
      appBar: AppBar(title: Text(event?.title ?? l10n.familyGallery)),
      body: gallery.isLoading && event == null
          ? const PlaceholderCards()
          : event == null
          ? FamilyEmptyView(icon: Icons.photo_library_rounded, title: l10n.familyGalleryGone)
          : ListView(
              key: const Key('family-gallery-event'),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  [event.dateLabel, _audience(context, event)].join(' · '),
                  style: TextStyle(color: context.appColors.muted),
                ),
                if (event.description != null) ...[const SizedBox(height: 8), Text(event.description!)],
                const SizedBox(height: 12),
                PhotoGrid(photos: event.photos, title: event.title),
              ],
            ),
    );
  }
}
