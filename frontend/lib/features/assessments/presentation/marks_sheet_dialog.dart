import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_picker.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../imports/data/import_repository.dart';
import '../../imports/data/models/import_result.dart';
import '../../imports/presentation/widgets/import_row_errors.dart';
import '../application/assessment_list_notifier.dart';
import '../application/assessment_sheet_notifier.dart';
import '../data/models/assessment.dart';
import '../data/models/assessment_sheet.dart';

/// The marks sheet for one class test (docs/assessments.md).
///
/// The whole class is on screen and the whole class is saved at once. A mark
/// and an absence are separate: absent is not zero, and a blank box is not a
/// zero either - it means nobody has said yet.
class MarksSheetDialog extends ConsumerStatefulWidget {
  const MarksSheetDialog({super.key, required this.assessment, required this.canManage});

  final Assessment assessment;

  /// False for a role that may see the test but not mark it, and for a test
  /// that has been published. The boxes are then read-only.
  final bool canManage;

  @override
  ConsumerState<MarksSheetDialog> createState() => _MarksSheetDialogState();
}

class _MarksSheetDialogState extends ConsumerState<MarksSheetDialog> {
  final Map<int, TextEditingController> _controllers = {};

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  /// The rows a rejected spreadsheet named. Read with the file open, so they
  /// are listed rather than summarised.
  List<ImportRowError> _rowErrors = const [];

  bool get _editable => widget.canManage && widget.assessment.isDraft;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(SheetEntry entry) {
    return _controllers.putIfAbsent(entry.studentId, () => TextEditingController(text: entry.marksForEditing));
  }

  /// The server keys a refusal by position on the sheet it was sent, so the
  /// row shows its own message.
  String? _rowError(int index) => _fieldErrors['marks.$index.marks_obtained']?.first;

  String? _rowStudentError(int index) => _fieldErrors['marks.$index.student_id']?.first;

  Future<void> _downloadTemplate() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final bytes = await ref.read(assessmentSheetProvider(widget.assessment.id).notifier).template();
      saveBytes(fileName: 'marks-${widget.assessment.id}.csv', bytes: bytes, mimeType: 'text/csv');
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload() async {
    final picked = await pickFile(accept: '.csv,text/csv');
    if (picked == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
      _rowErrors = const [];
    });

    try {
      await ref
          .read(assessmentSheetProvider(widget.assessment.id).notifier)
          .upload(fileName: picked.name, bytes: picked.bytes);

      if (mounted) {
        for (final entry in ref.read(assessmentSheetProvider(widget.assessment.id)).value?.entries ?? const []) {
          _controllers[entry.studentId]?.text = entry.marksForEditing;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marks uploaded.')));
      }
    } on BulkImportFailure catch (refusal) {
      if (mounted) {
        setState(() {
          _rowErrors = refusal.rows;
          _error = 'Nothing was uploaded. Fix the rows below and try again.';
        });
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish(AssessmentSheet sheet) async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish this result?'),
        content: Text(
          'Grades are worked out from the grade scale and fixed as they are now. The sheet closes, '
          'and only an administrator or the head of department can reopen it. '
          '${sheet.entries.length} in the class.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Publish')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
      _rowErrors = const [];
    });

    try {
      await ref.read(assessmentListNotifierProvider.notifier).publish(widget.assessment);

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Result published.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await ref.read(assessmentSheetProvider(widget.assessment.id).notifier).save();

      if (mounted) {
        // The controllers are rebuilt from what came back, so a mark the
        // server rounded reads as the server has it.
        for (final entry in ref.read(assessmentSheetProvider(widget.assessment.id)).value?.entries ?? const []) {
          _controllers[entry.studentId]?.text = entry.marksForEditing;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marks saved.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          _error = _fieldErrors.isEmpty ? failure.message : 'Some marks could not be saved. See the rows below.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetState = ref.watch(assessmentSheetProvider(widget.assessment.id));
    final assessment = widget.assessment;

    return AlertDialog(
      title: Text('Marks · ${assessment.title}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 520, maxHeight: 460),
        child: AsyncValueView<AssessmentSheet>(
          value: sheetState,
          onRetry: () => ref.read(assessmentSheetProvider(assessment.id).notifier).refresh(),
          isEmpty: (sheet) => sheet.entries.isEmpty,
          emptyBuilder: (context) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nobody is in this class yet, so there is nobody to mark.'),
          ),
          data: (context, sheet) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${assessment.classSectionName} · ${assessment.subjectName} · out of ${assessment.maxMarksLabel}',
                  style: TextStyle(color: context.appColors.muted),
                ),
                const SizedBox(height: 4),
                Text('${sheet.markedCount} of ${sheet.entries.length} marked'),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: context.appColors.danger)),
                ],
                if (_rowErrors.isNotEmpty) ...[const SizedBox(height: 8), ImportRowErrors(errors: _rowErrors)],
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: sheet.entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _Row(
                      entry: sheet.entries[index],
                      controller: _controllerFor(sheet.entries[index]),
                      editable: _editable && !_saving,
                      error: _rowError(index) ?? _rowStudentError(index),
                      onMark: (value) => ref
                          .read(assessmentSheetProvider(assessment.id).notifier)
                          .setMark(sheet.entries[index].studentId, value.trim()),
                      onAbsent: (value) {
                        ref
                            .read(assessmentSheetProvider(assessment.id).notifier)
                            .setAbsent(sheet.entries[index].studentId, value);
                        if (value) _controllers[sheet.entries[index].studentId]?.clear();
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        if (_editable) ...[
          // A teacher often has the marks in a spreadsheet already, and the
          // downloaded one comes with the class on it (docs/assessments.md).
          TextButton(onPressed: _saving ? null : _downloadTemplate, child: const Text('Download sheet')),
          if (canPickFile) TextButton(onPressed: _saving ? null : _upload, child: const Text('Upload sheet')),
        ],
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(_editable ? 'Cancel' : 'Done'),
        ),
        if (_editable && sheetState.value != null)
          TextButton(
            // Offered only once everybody has a mark or an absence: the API
            // refuses an incomplete class, and a button that always fails is
            // worse than one that waits.
            onPressed: _saving || !sheetState.value!.isComplete ? null : () => _publish(sheetState.value!),
            child: const Text('Publish'),
          ),
        if (_editable)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Marks'),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.controller,
    required this.editable,
    required this.error,
    required this.onMark,
    required this.onAbsent,
  });

  final SheetEntry entry;
  final TextEditingController controller;
  final bool editable;
  final String? error;
  final ValueChanged<String> onMark;
  final ValueChanged<bool> onAbsent;

  @override
  Widget build(BuildContext context) {
    final roll = entry.rollNumber;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.studentName),
                      Text(
                        roll == null ? entry.admissionNumber : 'Roll $roll · ${entry.admissionNumber}',
                        style: TextStyle(fontSize: 12, color: context.appColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (!editable && entry.isMarked) ...[_Result(entry: entry), const SizedBox(width: 8)],
              SizedBox(
                width: 110,
                child: TextField(
                  controller: controller,
                  enabled: editable && !entry.isAbsent,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Marks',
                    isDense: true,
                    // The message itself goes under the row, where there is
                    // room to read it: inside a box this narrow it was
                    // clipped to "The marks ...", which told nobody anything.
                    // The box still turns red, because that is what points at
                    // the row.
                    errorText: error == null ? null : '',
                    errorStyle: const TextStyle(height: 0),
                    hintText: entry.isAbsent ? 'Absent' : null,
                  ),
                  onChanged: onMark,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilterChip(
                  label: const Text('Absent'),
                  selected: entry.isAbsent,
                  onSelected: editable ? onAbsent : null,
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error!, style: TextStyle(color: context.appColors.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// What a published mark came to: the grade, the percentage, and whether it
/// was a pass. Shown instead of nothing once the sheet is closed, because a
/// closed sheet is read rather than typed into.
class _Result extends StatelessWidget {
  const _Result({required this.entry});

  final SheetEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isAbsent) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Absent', style: TextStyle(color: context.appColors.muted, fontSize: 12)),
      );
    }

    final passed = entry.passed;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.grade != null) ...[
            StatusBadge(label: entry.grade!, tone: passed == false ? BadgeTone.danger : BadgeTone.success),
            const SizedBox(width: 8),
          ],
          if (entry.percentage != null)
            Text('${Assessment.tidyMarks(entry.percentage)}%', style: TextStyle(color: context.appColors.muted)),
        ],
      ),
    );
  }
}
