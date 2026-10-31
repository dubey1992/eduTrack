import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/file_picker.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../application/site_page_notifiers.dart';
import '../../data/models/site_page.dart';
import '../../data/site_page_repository.dart';

const _coverExtensions = ['.jpg', '.jpeg', '.png'];
const _maxCoverBytes = 5 * 1024 * 1024;

/// A blog post's cover image (docs/seo.md, S5): shown at the top of the post,
/// on its card in the blog, and as its picture when shared.
///
/// Like the text, a new cover is a draft until the post is published. It can
/// only be added once the post has been saved, because it is stored against
/// the post's address.
class CoverField extends ConsumerStatefulWidget {
  const CoverField({super.key, required this.page, required this.onChanged});

  /// The post as the server last answered; null until its first save.
  final SitePageDetail? page;

  /// Called with the post as it now is, after a cover is added or removed.
  final ValueChanged<SitePageDetail> onChanged;

  @override
  ConsumerState<CoverField> createState() => _CoverFieldState();
}

class _CoverFieldState extends ConsumerState<CoverField> {
  Future<Uint8List?>? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(CoverField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page?.slug != widget.page?.slug || oldWidget.page?.hasCover != widget.page?.hasCover) {
      _loadPreview();
    }
  }

  void _loadPreview() {
    final page = widget.page;
    _preview = page != null && page.hasCover ? ref.read(sitePageRepositoryProvider).coverBytes(page.slug) : null;
  }

  /// What the server would refuse anyway, so a file that is too big is not
  /// uploaded only to be turned away.
  static String? _problemWith(PickedFile file) {
    final name = file.name.toLowerCase();
    if (!_coverExtensions.any(name.endsWith)) return 'The cover image must be a JPEG or PNG image.';
    if (file.bytes.length > _maxCoverBytes) return 'The cover image must be 5 MB or smaller.';
    return null;
  }

  Future<void> _choose() async {
    final page = widget.page;
    if (_busy || page == null) return;

    final PickedFile? file;
    try {
      file = await pickFile(accept: '.jpg,.jpeg,.png,image/jpeg,image/png');
    } catch (error) {
      debugPrint('Picking a cover image failed: $error');
      if (mounted) setState(() => _error = 'The image could not be read. Try another file.');
      return;
    }
    if (file == null || !mounted) return;

    final problem = _problemWith(file);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    await _run(
      () => ref
          .read(sitePageListNotifierProvider.notifier)
          .uploadCover(page.slug, bytes: file!.bytes, fileName: file.name),
      success: 'Cover image saved. Visitors see it once you publish the post.',
    );
  }

  Future<void> _remove() async {
    final page = widget.page;
    if (_busy || page == null) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Remove the cover image?',
      message: 'The post will show the School365ai picture instead, once you publish it.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(
      () => ref.read(sitePageListNotifierProvider.notifier).removeCover(page.slug),
      success: 'Cover image removed.',
    );
  }

  Future<void> _run(Future<SitePageDetail> Function() action, {required String success}) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final page = await action();
      if (!mounted) return;
      widget.onChanged(page);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() => _error = failure.validationErrors['cover']?.join(' ') ?? failure.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final muted = TextStyle(fontSize: 12, color: context.appColors.muted);

    return SizedBox(
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cover image', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1200 / 630,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(color: context.appColors.muted.withValues(alpha: 0.12), child: _previewImage()),
            ),
          ),
          const SizedBox(height: 6),
          if (page == null)
            Text('Save the post first, then add a cover image.', style: muted)
          else ...[
            Text('JPEG or PNG, up to 5 MB. Shown best at 1200 x 630.', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('cover-choose'),
                  onPressed: _busy ? null : _choose,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(page.hasCover ? 'Change image' : 'Choose image'),
                ),
                if (page.hasCover)
                  TextButton(
                    key: const Key('cover-remove'),
                    onPressed: _busy ? null : _remove,
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(fontSize: 12, color: context.appColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _previewImage() {
    final preview = _preview;
    if (preview == null) return const Center(child: Icon(Icons.image_outlined, size: 40));

    return FutureBuilder<Uint8List?>(
      future: preview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final bytes = snapshot.data;
        if (snapshot.hasError || bytes == null) return const Center(child: Icon(Icons.broken_image_outlined));

        return Image.memory(bytes, fit: BoxFit.cover, key: const Key('cover-preview'));
      },
    );
  }
}
