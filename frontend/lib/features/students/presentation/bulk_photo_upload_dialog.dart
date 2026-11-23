import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_picker.dart';
import '../application/bulk_photo_upload_notifier.dart';
import '../data/models/photo_import.dart';

/// Asks the person for several photos at once. Swappable in tests.
typedef PhotosPicker = Future<List<ChosenFile>> Function();

final photosPickerProvider = Provider<PhotosPicker>(
  (ref) =>
      () => pickFiles(accept: 'image/jpeg,image/png'),
);

/// "Upload Photos" on the Students page: a whole class's photos at once,
/// each file named after the student's admission number
/// (docs/student-photos.md, P2).
///
/// Four steps in one dialog: choose the photos, see what each one matches
/// before anything is sent, watch them go a batch at a time, and read what
/// happened to each. Nothing leaves the computer until "Upload" is pressed.
class BulkPhotoUploadDialog extends ConsumerWidget {
  const BulkPhotoUploadDialog({super.key, this.schoolId, this.onUploaded});

  /// Only a Super Admin sets this: they name the school.
  final int? schoolId;

  /// Called once photos have been stored, to refresh the list behind.
  final VoidCallback? onUploaded;

  Future<void> _choose(WidgetRef ref) async {
    final List<ChosenFile> files;
    try {
      files = await ref.read(photosPickerProvider)();
    } catch (error) {
      debugPrint('Choosing photos failed: $error');
      return;
    }
    await ref.read(bulkPhotoUploadProvider.notifier).check(files, schoolId: schoolId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bulkPhotoUploadProvider);
    final notifier = ref.read(bulkPhotoUploadProvider.notifier);
    final busy = state.step == BulkPhotoStep.checking || state.step == BulkPhotoStep.uploading;

    void finish() {
      if (state.results.any((result) => result.status != PhotoUploadStatus.skipped)) onUploaded?.call();
      Navigator.of(context).pop();
    }

    return PopScope(
      // Closing half-way would leave nobody watching the rest go.
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Upload student photos'),
        content: SizedBox(
          width: 640,
          child: switch (state.step) {
            BulkPhotoStep.choose => _ChooseStep(error: state.error),
            BulkPhotoStep.checking => _Working(text: 'Checking ${state.files.length} photos...'),
            BulkPhotoStep.preview => _PreviewStep(state: state),
            BulkPhotoStep.uploading || BulkPhotoStep.paused => _ProgressStep(state: state),
            BulkPhotoStep.done => _DoneStep(state: state),
          },
        ),
        actions: switch (state.step) {
          BulkPhotoStep.choose => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton.icon(
              key: const Key('bulk-photos-choose'),
              onPressed: () => _choose(ref),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Choose photos'),
            ),
          ],
          BulkPhotoStep.checking || BulkPhotoStep.uploading => const [],
          BulkPhotoStep.preview => [
            TextButton(
              key: const Key('bulk-photos-choose-again'),
              onPressed: notifier.reset,
              child: const Text('Choose other photos'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              key: const Key('bulk-photos-upload'),
              onPressed: state.toSend.isEmpty ? null : notifier.upload,
              child: Text(_uploadLabel(state.toSend.length)),
            ),
          ],
          BulkPhotoStep.paused => [
            TextButton(onPressed: finish, child: const Text('Stop here')),
            FilledButton(
              key: const Key('bulk-photos-retry'),
              onPressed: notifier.upload,
              child: const Text('Try again'),
            ),
          ],
          BulkPhotoStep.done => [
            FilledButton(key: const Key('bulk-photos-done'), onPressed: finish, child: const Text('Done')),
          ],
        },
      ),
    );
  }

  static String _uploadLabel(int count) => count == 1 ? 'Upload 1 photo' : 'Upload $count photos';
}

class _ChooseStep extends StatelessWidget {
  const _ChooseStep({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Name each photo after the student's admission number, for example ADM-1042.jpg, "
          'then choose them all at once - a whole folder, with Ctrl+A.',
        ),
        const SizedBox(height: 10),
        Text(
          'An admission number with a / can be written with - or _ instead: SPHS-26-01A01.jpg is SPHS/26/01A01. '
          'JPEG or PNG, up to 5 MB each. Every photo is cut to a passport shape, and a new photo replaces the old one.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            key: const Key('bulk-photos-error'),
            style: TextStyle(color: context.appColors.danger),
          ),
        ],
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [const LinearProgressIndicator(), const SizedBox(height: 12), Text(text)],
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.state});

  final BulkPhotoState state;

  @override
  Widget build(BuildContext context) {
    final adding = state.rows.where((row) => row.status == PhotoMatchStatus.newPhoto).length;
    final replacing = state.rows.where((row) => row.status == PhotoMatchStatus.replace).length;
    // What will not go is listed first: it is what somebody has to act on.
    final ordered = [
      ...state.rows.where((row) => !row.status.uploads),
      ...state.rows.where((row) => row.status.uploads),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (adding > 0) _Count(key: const Key('bulk-photos-count-new'), label: '$adding new', tone: _Tone.good),
            if (replacing > 0)
              _Count(
                key: const Key('bulk-photos-count-replace'),
                label: '$replacing replace a photo',
                tone: _Tone.info,
              ),
            if (state.heldBack > 0)
              _Count(key: const Key('bulk-photos-count-held'), label: '${state.heldBack} held back', tone: _Tone.bad),
          ],
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ordered.length,
              itemBuilder: (context, index) => _PreviewTile(row: ordered[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.row});

  final PhotoPreviewRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final student = row.student;
    final (icon, color) = switch (row.status) {
      PhotoMatchStatus.newPhoto => (Icons.add_a_photo_outlined, colors.success),
      PhotoMatchStatus.replace => (Icons.swap_horiz, Theme.of(context).colorScheme.primary),
      _ => (Icons.block, colors.danger),
    };
    final detail = row.status.uploads && student != null
        ? [
            student.name,
            student.admissionNumber,
            ?student.classSectionName,
            if (row.status == PhotoMatchStatus.replace) 'replaces the photo',
          ].join(' · ')
        : row.reason ?? '';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(row.fileName),
      subtitle: Text(detail),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.state});

  final BulkPhotoState state;

  @override
  Widget build(BuildContext context) {
    final total = state.toSend.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(key: const Key('bulk-photos-progress'), value: total == 0 ? null : state.sent / total),
        const SizedBox(height: 12),
        Text('Uploaded ${state.sent} of $total photos.'),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(
            '${state.error} The photos sent so far are kept. Try again to send the rest.',
            key: const Key('bulk-photos-error'),
            style: TextStyle(color: context.appColors.danger),
          ),
        ],
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.state});

  final BulkPhotoState state;

  @override
  Widget build(BuildContext context) {
    final skipped = state.results.where((result) => result.status == PhotoUploadStatus.skipped).toList();
    // Held back at the preview, and turned away when sent: one list of what
    // still needs a photo, with why.
    final notUploaded = [
      for (final row in state.rows.where((row) => !row.status.uploads)) (row.fileName, row.reason ?? 'Not uploaded.'),
      for (final result in skipped) (result.fileName, result.reason ?? 'Not uploaded.'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state.count(PhotoUploadStatus.added) > 0)
              _Count(
                key: const Key('bulk-photos-added'),
                label: '${state.count(PhotoUploadStatus.added)} added',
                tone: _Tone.good,
              ),
            if (state.count(PhotoUploadStatus.replaced) > 0)
              _Count(
                key: const Key('bulk-photos-replaced'),
                label: '${state.count(PhotoUploadStatus.replaced)} replaced',
                tone: _Tone.info,
              ),
            if (notUploaded.isNotEmpty)
              _Count(
                key: const Key('bulk-photos-skipped'),
                label: '${notUploaded.length} not uploaded',
                tone: _Tone.bad,
              ),
          ],
        ),
        if (notUploaded.isNotEmpty) ...[
          const SizedBox(height: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (fileName, reason) in notUploaded)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.block, color: context.appColors.danger, size: 20),
                      title: Text(fileName),
                      subtitle: Text(reason),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _Tone { good, info, bad }

class _Count extends StatelessWidget {
  const _Count({super.key, required this.label, required this.tone});

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      _Tone.good => colors.success,
      _Tone.info => scheme.primary,
      _Tone.bad => colors.danger,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
