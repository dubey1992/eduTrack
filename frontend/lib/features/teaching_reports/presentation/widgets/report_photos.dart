import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/photo_picker.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/user_avatar.dart' show userPhotoProvider;
import '../../data/models/teaching_report.dart';
import '../../data/teaching_report_repository.dart';

/// A report's photos - the board, the children's work (docs/mobile-apps-
/// review.md, M9, 6.6). Everyone who may read the report sees them; its
/// teacher adds and removes them until it is reviewed. Staff only: parents
/// never see a report.
///
/// [onChanged] gets the report as the server returned it after a change.
class ReportPhotos extends ConsumerStatefulWidget {
  const ReportPhotos({super.key, required this.report, required this.canChange, required this.onChanged});

  final TeachingReport report;

  /// The report's own teacher, and the report not yet reviewed.
  final bool canChange;
  final ValueChanged<TeachingReport> onChanged;

  @override
  ConsumerState<ReportPhotos> createState() => _ReportPhotosState();
}

class _ReportPhotosState extends ConsumerState<ReportPhotos> {
  bool _busy = false;
  String? _problem;

  Future<void> _add() async {
    if (_busy) return;

    PhotoSource? source = PhotoSource.gallery;
    if (!kIsWeb) {
      source = await showModalBottomSheet<PhotoSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('report-photo-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(context.l10n.staffTakeAPhoto),
                onTap: () => Navigator.of(context).pop(PhotoSource.camera),
              ),
              ListTile(
                key: const Key('report-photo-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(context.l10n.staffChooseFromPhotos),
                onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (source == null || !mounted) return;

    final picked = await ref.read(photoPickerProvider)(source);
    if (picked == null || !mounted) return;

    await _change(
      () =>
          ref.read(teachingReportRepositoryProvider).addPhoto(widget.report.id, name: picked.name, bytes: picked.bytes),
      done: context.l10n.staffPhotoAdded,
    );
  }

  Future<void> _remove(ReportPhoto photo) async {
    final l10n = context.l10n;
    final sure = await confirmDialog(
      context,
      title: l10n.staffRemovePhotoQ,
      message: l10n.staffRemovePhotoBody,
      confirmLabel: l10n.staffRemove,
      isDestructive: true,
    );
    if (!sure || !mounted) return;

    await _change(
      () => ref.read(teachingReportRepositoryProvider).removePhoto(widget.report.id, photo.id),
      done: l10n.staffPhotoRemoved,
    );
  }

  Future<void> _change(Future<TeachingReport> Function() call, {required String done}) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final updated = await call();
      widget.onChanged(updated);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(
        () => _problem = failure.code == 'NETWORK_ERROR'
            ? context.l10n.staffNoConnectionTryLater
            : failure.validationErrors['photo']?.first ?? failure.localizedMessage(context),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.report.photos;
    final colors = context.appColors;
    final l10n = context.l10n;
    final canAdd = widget.canChange && photos.length < maxReportPhotos;

    if (photos.isEmpty && !widget.canChange) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        key: const Key('report-photos'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.staffPhotos, style: TextStyle(color: colors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in photos)
                _Thumbnail(photo: photo, onRemove: widget.canChange && !_busy ? () => _remove(photo) : null),
              if (canAdd)
                SizedBox.square(
                  dimension: 88,
                  child: OutlinedButton(
                    key: const Key('report-photo-add'),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: _busy ? null : _add,
                    child: _busy
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_a_photo_outlined),
                              const SizedBox(height: 4),
                              Text(l10n.staffAdd),
                            ],
                          ),
                  ),
                ),
            ],
          ),
          if (widget.canChange && photos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.staffReportPhotosHint(maxReportPhotos),
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _problem!,
                key: const Key('report-photo-problem'),
                style: TextStyle(color: colors.danger),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.photo, required this.onRemove});

  final ReportPhoto photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(userPhotoProvider(photo.url));
    final placeholder = Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);

    return Stack(
      key: Key('report-photo-${photo.id}'),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.square(
            dimension: 88,
            child: bytes.when(
              loading: () => placeholder,
              error: (_, _) => Center(child: Icon(Icons.broken_image_outlined, color: context.appColors.muted)),
              data: (data) => InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    key: const Key('report-photo-full'),
                    clipBehavior: Clip.antiAlias,
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Image.memory(
                        data,
                        fit: BoxFit.contain,
                        errorBuilder: (context, _, _) => Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(context.l10n.staffPhotoNotShown, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
                ),
                child: Image.memory(
                  data,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      Center(child: Icon(Icons.broken_image_outlined, color: context.appColors.muted)),
                ),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              key: Key('report-photo-remove-${photo.id}'),
              tooltip: context.l10n.staffRemovePhoto,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
  }
}
