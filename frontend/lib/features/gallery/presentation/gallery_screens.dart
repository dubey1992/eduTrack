import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/photo_picker.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/signed_in_image.dart';
import '../application/gallery_providers.dart';
import '../data/gallery_models.dart';
import 'gallery_event_dialog.dart';

/// Events and photos for parents (docs/mobile-apps-review.md, M12, 8.6), as
/// the school posts them: admins to the whole school or a class, a class
/// teacher to their own class.
class GalleryEventsScreen extends ConsumerWidget {
  const GalleryEventsScreen({super.key, this.compact = false});

  /// The Staff app's own screen: its app bar has the title.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final events = ref.watch(galleryEventsProvider);

    final post = FilledButton.icon(
      key: const Key('gallery-new'),
      onPressed: () async {
        final made = await showDialog<GalleryEvent>(context: context, builder: (_) => const GalleryEventDialog());
        if (made != null && context.mounted) context.push('/gallery/${made.id}');
      },
      icon: const Icon(Icons.add_a_photo_outlined),
      label: Text(l10n.galleryNewEvent),
    );

    return ListView(
      padding: EdgeInsets.only(top: compact ? 12 : 0, bottom: 24),
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(alignment: Alignment.centerLeft, child: post),
          )
        else
          SectionHeader(title: l10n.galleryHeading, actions: [post]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(l10n.galleryIntro, style: TextStyle(color: context.appColors.muted)),
        ),
        const SizedBox(height: 12),
        AsyncValueView(
          value: events,
          onRetry: () => ref.read(galleryEventsProvider.notifier).refresh(),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(l10n.galleryNoEvents, style: TextStyle(color: context.appColors.muted)),
            ),
          ),
          data: (context, page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final event in page.items) ...[_EventCard(event: event), const SizedBox(height: 10)],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String galleryAudience(BuildContext context, GalleryEvent event) =>
    event.className == null ? context.l10n.galleryWholeSchool : context.l10n.galleryParentsOf(event.className!);

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final GalleryEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = context.appColors.muted;

    return Card(
      key: Key('gallery-event-${event.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/gallery/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                [
                  event.dateLabel,
                  galleryAudience(context, event),
                  l10n.galleryPhotoCount(event.photos.length),
                ].join(' · '),
                style: TextStyle(color: muted),
              ),
              if (event.photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      for (final photo in event.photos.take(4)) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(width: 72, height: 72, child: SignedInImage(url: photo.thumbUrl)),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.galleryNoPhotosYetParents, style: TextStyle(color: muted, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One event: its photos, and - for whoever may change it - adding,
/// removing, editing and deleting.
class GalleryEventScreen extends ConsumerStatefulWidget {
  const GalleryEventScreen({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<GalleryEventScreen> createState() => _GalleryEventScreenState();
}

class _GalleryEventScreenState extends ConsumerState<GalleryEventScreen> {
  bool _uploading = false;

  GalleryEventNotifier get _notifier => ref.read(galleryEventProvider(widget.eventId).notifier);

  Future<PhotoSource?> _source() async {
    if (kIsWeb) return PhotoSource.gallery;
    final l10n = context.l10n;
    return showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('gallery-source-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.galleryTakePhoto),
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            ListTile(
              key: const Key('gallery-source-photos'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.galleryChoosePhoto),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    if (_uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final source = await _source();
    if (source == null) return;
    final file = await ref.read(photoPickerProvider)(source);
    if (file == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      await _notifier.addPhoto(file);
      messenger.showSnackBar(SnackBar(content: Text(l10n.galleryPhotoAdded)));
    } on Failure catch (failure) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.l10n.cancel)),
            FilledButton(
              key: const Key('gallery-confirm'),
              style: FilledButton.styleFrom(backgroundColor: context.appColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(yes),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _removePhoto(GalleryPhoto photo) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(l10n.galleryRemovePhotoQ, l10n.galleryRemovePhotoBody, l10n.galleryRemove)) return;
    try {
      await _notifier.removePhoto(photo.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.galleryPhotoRemoved)));
    } on Failure catch (failure) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }

  Future<void> _delete(GalleryEvent event) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (!await _confirm(l10n.galleryDeleteEventQ(event.title), l10n.galleryDeleteEventBody, l10n.galleryDelete)) {
      return;
    }
    try {
      await _notifier.delete();
      messenger.showSnackBar(SnackBar(content: Text(l10n.galleryEventDeleted)));
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/gallery');
      }
    } on Failure catch (failure) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = context.appColors.muted;

    return AsyncValueView<GalleryEvent>(
      value: ref.watch(galleryEventProvider(widget.eventId)),
      onRetry: () => _notifier.refresh(),
      data: (context, event) {
        final full = event.photos.length >= galleryMaxPhotos;
        return ListView(
          key: const Key('gallery-event'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(event.title, style: Theme.of(context).textTheme.titleLarge),
            Text(
              [
                event.dateLabel,
                galleryAudience(context, event),
                if (event.postedBy != null) event.postedBy!,
              ].join(' · '),
              style: TextStyle(color: muted),
            ),
            if (event.description != null) ...[const SizedBox(height: 8), Text(event.description!)],
            const SizedBox(height: 12),
            if (event.canChange)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('gallery-add-photo'),
                    onPressed: _uploading || full ? null : _add,
                    icon: _uploading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_a_photo_outlined),
                    label: Text(_uploading ? l10n.galleryUploading : l10n.galleryAddPhoto),
                  ),
                  OutlinedButton.icon(
                    key: const Key('gallery-edit'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => GalleryEventDialog(event: event),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l10n.galleryChange),
                  ),
                  TextButton.icon(
                    key: const Key('gallery-delete'),
                    onPressed: () => _delete(event),
                    icon: Icon(Icons.delete_outline_rounded, color: context.appColors.danger),
                    label: Text(l10n.galleryDelete, style: TextStyle(color: context.appColors.danger)),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              full ? l10n.galleryFull(galleryMaxPhotos) : l10n.galleryPhotosOf(event.photos.length, galleryMaxPhotos),
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (event.photos.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(l10n.galleryNoPhotosYet, style: TextStyle(color: muted)),
                ),
              )
            else
              PhotoGrid(photos: event.photos, title: event.title, onRemove: event.canChange ? _removePhoto : null),
          ],
        );
      },
    );
  }
}

/// An event's photos as small squares; a tap opens them full screen.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.photos, required this.title, this.onRemove});

  final List<GalleryPhoto> photos;
  final String title;
  final void Function(GalleryPhoto photo)? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              button: true,
              label: l10n.galleryPhotoLabel(index + 1, photos.length),
              excludeSemantics: true,
              child: InkWell(
                key: Key('gallery-photo-${photo.id}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PhotoViewer(urls: [for (final p in photos) p.url], initialIndex: index, title: title),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SignedInImage(url: photo.thumbUrl),
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  key: Key('gallery-remove-${photo.id}'),
                  tooltip: l10n.galleryRemovePhoto,
                  onPressed: () => onRemove!(photo),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        );
      },
    );
  }
}
