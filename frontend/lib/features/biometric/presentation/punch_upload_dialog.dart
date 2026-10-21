import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_picker.dart';
import '../../transport/presentation/widgets/submit_button.dart';
import '../application/punch_page_notifier.dart';
import '../data/biometric_repository.dart';
import '../data/models/biometric_punch.dart';

/// Uploading a punch file exported from the device software.
///
/// The fallback for a school whose devices cannot reach the internet, and
/// what makes this feature work before any device integration exists at all
/// (docs/biometric.md).
///
/// **Uploading the same file twice is safe**, and the dialog says so before
/// anybody does it: punches already in are counted, not duplicated. That is
/// the question somebody asks themselves while hesitating over the button.
class PunchUploadDialog extends ConsumerStatefulWidget {
  const PunchUploadDialog({super.key, this.schoolId, this.pick = pickFile});

  final int? schoolId;

  /// How the file is chosen. The real picker needs a browser, so a test
  /// hands in its own and drives the dialog the way a person does.
  final Future<PickedFile?> Function({required String accept}) pick;

  @override
  ConsumerState<PunchUploadDialog> createState() => _PunchUploadDialogState();
}

class _PunchUploadDialogState extends ConsumerState<PunchUploadDialog> {
  PickedFile? _file;
  bool _isSubmitting = false;
  String? _errorMessage;
  PunchUploadResult? _result;

  Future<void> _choose() async {
    final picked = await widget.pick(accept: '.csv,text/csv');

    if (picked == null || !mounted) return;

    setState(() {
      _file = picked;
      _errorMessage = null;
      _result = null;
    });
  }

  Future<void> _submit() async {
    final file = _file;

    if (_isSubmitting || file == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(biometricRepositoryProvider)
          .uploadPunches(fileName: file.name, bytes: file.bytes, schoolId: widget.schoolId);

      await ref.read(punchPageNotifierProvider.notifier).refresh();

      if (mounted) setState(() => _result = result);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final result = _result;

    return AlertDialog(
      title: const Text('Upload punches'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: TextStyle(color: colors.danger)),
                const SizedBox(height: 12),
              ],
              if (result == null) ...[
                const Text('A CSV exported from the device software, with two columns:'),
                const SizedBox(height: 6),
                SelectableText(
                  'biometric_user_id,punched_at\n17,10/20/2026 09:02',
                  style: TextStyle(fontFamily: 'monospace', color: colors.muted),
                ),
                const SizedBox(height: 10),
                Text(
                  'Uploading the same file twice is safe - punches already in are '
                  'counted, not duplicated. A line that cannot be read is listed '
                  'rather than refusing the whole file.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _choose,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Choose file'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_file?.name ?? 'No file chosen', style: TextStyle(color: colors.muted)),
                    ),
                  ],
                ),
              ] else
                _Outcome(result: result),
            ],
          ),
        ),
      ),
      actions: result == null
          ? [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              SubmitButton(isSubmitting: _isSubmitting, onPressed: _file == null ? null : _submit, label: 'Upload'),
            ]
          : [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

/// What the file did. Shown instead of a bare "uploaded", because the three
/// numbers are the whole answer: what is new, what was already in, and what
/// did not read.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.result});

  final PunchUploadResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${result.accepted} new', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (result.duplicate > 0)
          Text(
            '${result.duplicate} already in - devices resend, and exports overlap.',
            style: TextStyle(color: colors.muted),
          ),
        if (result.hasProblems) ...[
          const SizedBox(height: 12),
          Text('${result.refused.length} line(s) could not be read:', style: TextStyle(color: colors.warning)),
          const SizedBox(height: 4),
          // Every one, not the first: one upload should tell somebody all of
          // it, so the file can be fixed once.
          for (final line in result.refused)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ],
    );
  }
}
