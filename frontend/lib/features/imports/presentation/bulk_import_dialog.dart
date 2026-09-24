import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_picker.dart';
import '../../../core/utils/file_saver.dart';
import '../../auth/application/auth_notifier.dart';
import '../data/import_repository.dart';
import '../data/models/import_preview.dart';
import '../data/models/import_result.dart';
import 'widgets/import_preview_table.dart';
import 'widgets/import_row_errors.dart';
import 'widgets/import_summary.dart';

/// Upload a spreadsheet of records.
///
/// Three states in one dialog, because they are three steps of one job:
/// choose a file, see what was wrong with it, or see what it produced. The
/// middle one is the reason this is a dialog and not a snack bar - a list of
/// twelve rows to fix is something you read with the spreadsheet open.
class BulkImportDialog extends ConsumerStatefulWidget {
  const BulkImportDialog({super.key, required this.type, required this.title, this.schoolId, this.onImported});

  /// The path segment the API knows this kind of record by - 'students',
  /// 'staff', 'subjects', 'vehicles', 'drivers'.
  final String type;

  /// What the file contains, in the plural: 'Students', 'Vehicles'.
  final String title;

  /// Only ever set by a Super Admin, who belongs to no school and has to say
  /// which one they are importing into.
  final int? schoolId;

  /// Called after a successful import, to refresh the list behind.
  final VoidCallback? onImported;

  @override
  ConsumerState<BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends ConsumerState<BulkImportDialog> {
  PickedFile? _file;
  bool _isBusy = false;
  String? _errorMessage;
  List<ImportRowError> _rowErrors = const [];

  /// What the chosen file would import. Shown before anything is written,
  /// because a file that passes still lands unseen otherwise, and there is
  /// no undo for a hundred records made from the wrong spreadsheet.
  ImportPreview? _preview;
  ImportResult? _result;

  Future<void> _downloadTemplate() async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      final bytes = await ref.read(importRepositoryProvider).downloadTemplate(widget.type);
      saveBytes(fileName: '${widget.type}-template.csv', bytes: bytes, mimeType: 'text/csv');
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _choose() async {
    final file = await pickFile(accept: '.csv,text/csv');

    if (file != null && mounted) {
      setState(() {
        _file = file;
        _errorMessage = null;
        _rowErrors = const [];
        _preview = null;
      });
    }
  }

  Future<void> _previewFile() async {
    final file = _file;
    if (file == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _rowErrors = const [];
    });

    try {
      final preview = await ref
          .read(importRepositoryProvider)
          .preview(type: widget.type, fileName: file.name, bytes: file.bytes, schoolId: widget.schoolId);

      if (mounted) setState(() => _preview = preview);
    } on BulkImportFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.message;
          _rowErrors = failure.rows;
        });
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _rowErrors = const [];
    });

    try {
      final result = await ref
          .read(importRepositoryProvider)
          .import(type: widget.type, fileName: file.name, bytes: file.bytes, schoolId: widget.schoolId);

      widget.onImported?.call();
      if (mounted) setState(() => _result = result);
    } on BulkImportFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.message;
          _rowErrors = failure.rows;
        });
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    // A Super Admin belongs to no school, so the list's school filter is
    // what says where these records go. Without it there is nowhere to put
    // them, and the API would only say so after the upload.
    final needsSchool = ref.watch(authNotifierProvider).value?.role == UserRole.superAdmin && widget.schoolId == null;

    final preview = _preview;

    return AlertDialog(
      title: Text(_titleFor(result, preview)),
      content: SizedBox(width: 620, child: SingleChildScrollView(child: _body(context, result, preview, needsSchool))),
      actions: _actionsFor(context, result, preview, needsSchool),
    );
  }

  String _titleFor(ImportResult? result, ImportPreview? preview) {
    if (result != null) return 'Imported';
    if (preview != null) return 'Check before importing';

    return 'Bulk Upload ${widget.title}';
  }

  Widget _body(BuildContext context, ImportResult? result, ImportPreview? preview, bool needsSchool) {
    if (result != null) return ImportSummary(result: result);
    if (preview != null) return ImportPreviewTable(preview: preview);

    return _form(context, needsSchool);
  }

  List<Widget> _actionsFor(BuildContext context, ImportResult? result, ImportPreview? preview, bool needsSchool) {
    if (result != null) {
      return [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))];
    }

    if (preview != null) {
      return [
        // Back to the file rather than out of the dialog: the usual reason to
        // stop here is that the wrong file was chosen.
        TextButton(
          onPressed: _isBusy ? null : () => setState(() => _preview = null),
          child: const Text('Choose another file'),
        ),
        FilledButton(
          onPressed: _isBusy ? null : _upload,
          child: _isBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Import ${preview.rowCount}'),
        ),
      ];
    }

    return [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _file == null || _isBusy || needsSchool ? null : _previewFile,
        child: _isBusy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Check file'),
      ),
    ];
  }

  Widget _form(BuildContext context, bool needsSchool) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (needsSchool) ...[
          Text(
            'Choose a school in the filter first - that is the school these records will be added to.',
            style: TextStyle(color: context.appColors.danger),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Download the template, fill in one row per record, and upload it as a CSV. '
          'Nothing is imported unless every row is valid.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _downloadTemplate,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Download template'),
            ),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _choose,
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(_file == null ? 'Choose file' : 'Choose another file'),
            ),
            if (_file != null)
              Text(_file!.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
        ],
        if (_rowErrors.isNotEmpty) ...[const SizedBox(height: 12), ImportRowErrors(errors: _rowErrors)],
      ],
    );
  }
}
