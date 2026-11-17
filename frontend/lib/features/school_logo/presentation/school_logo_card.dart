import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/photo_picker.dart';
import '../../../core/utils/picked_file.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/school_logo_controller.dart';
import '../data/school_logo_repository.dart';
import 'school_logo_image.dart';

/// The logo as it is now, and the buttons to upload, replace or remove it
/// (docs/school-logo.md). Used by the sign-in reminder, School Profile and
/// the Super Admin's school page; the server decides who may.
class SchoolLogoCard extends ConsumerStatefulWidget {
  const SchoolLogoCard({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.logoUrl,
    this.allowRemove = true,
    this.onChanged,
  });

  final int schoolId;
  final String schoolName;
  final String? logoUrl;

  /// The reminder only offers an upload; removing is for School Profile.
  final bool allowRemove;

  /// Told after a successful upload or removal, with what the server said.
  final ValueChanged<SchoolLogoResult>? onChanged;

  @override
  ConsumerState<SchoolLogoCard> createState() => _SchoolLogoCardState();
}

class _SchoolLogoCardState extends ConsumerState<SchoolLogoCard> {
  bool _busy = false;
  String? _error;

  /// What was just uploaded, shown before the session catches up.
  String? _shownUrl;
  bool _changed = false;

  String? get _logoUrl => _changed ? _shownUrl : widget.logoUrl;

  Future<void> _upload() async {
    if (_busy) return;

    final PickedFile? file;
    try {
      file = await ref.read(photoPickerProvider)(PhotoSource.gallery);
    } catch (error) {
      debugPrint('Picking a school logo failed: $error');
      if (mounted) setState(() => _error = 'The image could not be read. Try another file.');
      return;
    }
    if (file == null || !mounted) return;

    final chosen = file;
    final problem = logoProblem(fileName: chosen.name, length: chosen.bytes.length);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    await _run(
      () => ref
          .read(schoolLogoControllerProvider)
          .upload(schoolId: widget.schoolId, bytes: chosen.bytes, fileName: chosen.name),
      success: 'Logo saved. Your school profile is complete.',
    );
  }

  Future<void> _remove() async {
    if (_busy) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Remove the logo?',
      message:
          'The school\'s initials will show in the menu instead, and documents will print without a logo. '
          'Your School Admins will be asked for a new one at every sign-in.',
      confirmLabel: 'Remove logo',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(schoolLogoControllerProvider).remove(widget.schoolId), success: 'Logo removed.');
  }

  Future<void> _run(Future<SchoolLogoResult> Function() change, {required String success}) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await change();
      if (!mounted) return;
      setState(() {
        _changed = true;
        _shownUrl = result.logoUrl;
      });
      messenger
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(success)));
      widget.onChanged?.call(result);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.validationErrors['logo']?.first ?? failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final hasLogo = _logoUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              SchoolLogoImage(logoUrl: _logoUrl, schoolName: widget.schoolName, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLogo ? 'Your school\'s logo' : 'No logo yet',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PNG or JPG, up to 2 MB. A square logo of at least 200 × 200 pixels looks best.',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (hasLogo && widget.allowRemove)
              TextButton.icon(
                key: const Key('school-logo-remove'),
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove logo'),
              ),
            FilledButton.icon(
              key: const Key('school-logo-upload'),
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: Text(hasLogo ? 'Replace logo' : 'Upload logo'),
            ),
          ],
        ),
        if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const Key('school-logo-error'),
            style: TextStyle(color: colors.danger, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
