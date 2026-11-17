import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../classes/data/models/school_class.dart';
import '../../subjects/data/models/subject.dart';
import '../../timetable/application/subject_picker_provider.dart';
import '../application/examination_providers.dart';
import '../data/models/examination.dart';
import 'examination_dialog.dart';

/// The exam's date sheet: one row per paper - a class, a subject, a day and
/// a time (docs/examinations.md). Edited here and saved as a whole; the
/// server checks the year's dates, one paper per subject per class and that
/// a class never sits two papers at once, and its sentence lands on the row.
class DateSheetEditor extends ConsumerStatefulWidget {
  const DateSheetEditor({super.key, required this.exam, required this.canEdit});

  final Examination exam;
  final bool canEdit;

  @override
  ConsumerState<DateSheetEditor> createState() => _DateSheetEditorState();
}

class _Row {
  _Row({this.classId, this.subjectId, this.date, this.start = '09:00', this.end = '12:00'});

  factory _Row.of(ExamPaper paper) => _Row(
    classId: paper.schoolClassId,
    subjectId: paper.subjectId,
    date: paper.examDate,
    start: paper.startTime,
    end: paper.endTime,
  );

  int? classId;
  int? subjectId;
  String? date;
  String start;
  String end;
}

class _DateSheetEditorState extends ConsumerState<DateSheetEditor> {
  late List<_Row> _rows = _fromExam();
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  List<_Row> _fromExam() => [for (final paper in widget.exam.papers) _Row.of(paper)];

  @override
  void didUpdateWidget(covariant DateSheetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.exam != widget.exam) _rows = _fromExam();
  }

  void _changed(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  String? _rowError(int index, String field) => _fieldErrors['papers.$index.$field']?.first;

  Future<void> _pickDate(_Row row) async {
    final initial = row.date != null ? DateTime.parse(row.date!) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2),
    );
    if (picked != null) _changed(() => row.date = apiDate(picked));
  }

  Future<void> _pickTime(_Row row, {required bool start}) async {
    final parts = (start ? row.start : row.end).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    _changed(() {
      if (start) {
        row.start = hhmm(picked);
      } else {
        row.end = hhmm(picked);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final incomplete = _rows.indexWhere((row) => row.classId == null || row.subjectId == null || row.date == null);
    if (incomplete >= 0) {
      setState(() => _error = 'Row ${incomplete + 1} needs a class, a subject and a date.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(examinationProvider(widget.exam.id).notifier).savePapers([
        for (final row in _rows)
          ExamPaper(
            schoolClassId: row.classId!,
            subjectId: row.subjectId!,
            examDate: row.date!,
            startTime: row.start,
            endTime: row.end,
          ),
      ]);
      if (!mounted) return;
      setState(() => _dirty = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.exam.isPublished
                ? 'Date sheet saved. Publish again for cards to show the change.'
                : 'Date sheet saved.',
          ),
        ),
      );
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (!mounted) return;
      setState(() {
        _fieldErrors = failure.validationErrors;
        _error = failure.message;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = ref.watch(examClassesProvider(widget.exam.academicYearId)).value ?? const <SchoolClass>[];
    final subjects = ref.watch(subjectPickerProvider(null)).value ?? const <Subject>[];
    final colors = context.appColors;
    final canEdit = widget.canEdit;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          canEdit
              ? 'One row per paper. Times are the school\'s own clock. Save the sheet, then publish so the cards '
                    'show it.'
              : 'The papers each class sits.',
          style: TextStyle(color: colors.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          Text(
            _error!,
            key: const Key('sheet-error'),
            style: TextStyle(color: colors.danger),
          ),
          const SizedBox(height: 8),
        ],
        if (_rows.isEmpty)
          Padding(
            key: const Key('sheet-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(canEdit ? 'No papers yet. Add the first one.' : 'No papers yet.', textAlign: TextAlign.center),
          ),
        for (var index = 0; index < _rows.length; index++) _rowEditor(index, _rows[index], classes, subjects, canEdit),
        if (canEdit) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('sheet-add'),
                onPressed: _saving
                    ? null
                    : () => _changed(() {
                        // A new row copies the class and times of the last, so
                        // a class's whole sheet is quick to type.
                        final last = _rows.isEmpty ? null : _rows.last;
                        _rows.add(
                          _Row(classId: last?.classId, start: last?.start ?? '09:00', end: last?.end ?? '12:00'),
                        );
                      }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add paper'),
              ),
              FilledButton(
                key: const Key('sheet-save'),
                onPressed: _dirty && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save date sheet'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _rowEditor(int index, _Row row, List<SchoolClass> classes, List<Subject> subjects, bool canEdit) {
    final colors = context.appColors;
    final rowErrors = [
      for (final field in ['school_class_id', 'subject_id', 'exam_date', 'start_time', 'end_time'])
        ?_rowError(index, field),
    ];

    return Card(
      key: Key('sheet-row-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int>(
                    key: Key('sheet-class-$index'),
                    initialValue: classes.any((c) => c.id == row.classId) ? row.classId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Class', isDense: true),
                    items: [for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))],
                    onChanged: canEdit ? (value) => _changed(() => row.classId = value) : null,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: Key('sheet-subject-$index'),
                    initialValue: subjects.any((s) => s.id == row.subjectId) ? row.subjectId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Subject', isDense: true),
                    items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))],
                    onChanged: canEdit ? (value) => _changed(() => row.subjectId = value) : null,
                  ),
                ),
                OutlinedButton.icon(
                  key: Key('sheet-date-$index'),
                  onPressed: canEdit ? () => _pickDate(row) : null,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(row.date == null ? 'Choose date' : formatIsoDate(row.date)),
                ),
                OutlinedButton(
                  key: Key('sheet-start-$index'),
                  onPressed: canEdit ? () => _pickTime(row, start: true) : null,
                  child: Text(formatClock(row.start)),
                ),
                const Text('to'),
                OutlinedButton(
                  key: Key('sheet-end-$index'),
                  onPressed: canEdit ? () => _pickTime(row, start: false) : null,
                  child: Text(formatClock(row.end)),
                ),
                if (canEdit)
                  IconButton(
                    key: Key('sheet-remove-$index'),
                    tooltip: 'Remove paper',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _changed(() => _rows.removeAt(index)),
                  ),
              ],
            ),
            for (final message in rowErrors)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(message, style: TextStyle(color: colors.danger, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
