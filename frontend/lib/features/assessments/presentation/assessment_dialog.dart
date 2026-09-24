import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../academic_years/application/academic_term_notifier.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_term.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../../grade_scales/application/grade_scale_notifier.dart';
import '../../subjects/data/models/subject.dart';
import '../../timetable/application/subject_picker_provider.dart';
import '../application/assessment_list_notifier.dart';
import '../data/models/assessment.dart';

/// Set a class test, or edit one (docs/assessments.md).
///
/// The class and the subject are chosen once and then fixed: moving a test
/// to another class would carry its marks with it, which is not an edit of a
/// title and a date. The form shows them as plain text when editing.
class AssessmentDialog extends ConsumerStatefulWidget {
  const AssessmentDialog({super.key, this.assessment});

  final Assessment? assessment;

  @override
  ConsumerState<AssessmentDialog> createState() => _AssessmentDialogState();
}

class _AssessmentDialogState extends ConsumerState<AssessmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.assessment?.title ?? '');
  late final _maxMarksController = TextEditingController(text: Assessment.tidyMarks(widget.assessment?.maxMarks) ?? '');
  late final _passMarksController = TextEditingController(
    text: Assessment.tidyMarks(widget.assessment?.passMarks) ?? '',
  );
  late final _weightageController = TextEditingController(
    text: Assessment.tidyMarks(widget.assessment?.weightage) ?? '',
  );

  late int? _sectionId = widget.assessment?.classSectionId;
  late int? _subjectId = widget.assessment?.subjectId;
  late int? _termId = widget.assessment?.academicTermId;
  late int? _gradeScaleId = widget.assessment?.gradeScaleId;
  late AssessmentType _type = widget.assessment?.type ?? AssessmentType.classTest;
  late DateTime? _date = widget.assessment?.assessmentDate;

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.assessment != null;

  @override
  void dispose() {
    _titleController.dispose();
    _maxMarksController.dispose();
    _passMarksController.dispose();
    _weightageController.dispose();
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    if (!_isEdit && (_sectionId == null || _subjectId == null)) {
      setState(() => _error = 'Choose the class and the subject this test is for.');
      return;
    }
    if (_termId == null) {
      setState(() => _error = 'Choose the term this test belongs to.');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Choose the date of the test.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final notifier = ref.read(assessmentListNotifierProvider.notifier);
    final title = _titleController.text.trim();
    final maxMarks = _maxMarksController.text.trim();
    final passMarks = _passMarksController.text.trim();
    final weightage = _weightageController.text.trim();

    try {
      if (_isEdit) {
        await notifier.updateAssessment(
          widget.assessment!,
          academicTermId: _termId,
          gradeScaleId: _gradeScaleId,
          type: _type.apiValue,
          title: title,
          maxMarks: maxMarks,
          passMarks: passMarks.isEmpty ? null : passMarks,
          weightage: weightage.isEmpty ? null : weightage,
          assessmentDate: _date,
        );
      } else {
        await notifier.createAssessment(
          classSectionId: _sectionId!,
          subjectId: _subjectId!,
          academicTermId: _termId!,
          gradeScaleId: _gradeScaleId,
          type: _type.apiValue,
          title: title,
          maxMarks: maxMarks,
          passMarks: passMarks.isEmpty ? null : passMarks,
          weightage: weightage.isEmpty ? null : weightage,
          assessmentDate: _date!,
        );
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(_isEdit ? 'Test updated.' : 'Test created.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // Anything keyed to a field is shown on that field; only what is
          // left over needs the banner.
          _error = _fieldErrors.isEmpty ? failure.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = ref.watch(classSectionPickerProvider(null));
    final subjects = ref.watch(subjectPickerProvider(null));
    final years = ref.watch(academicYearPickerProvider(null));
    final currentYear = years.value?.where((year) => year.isCurrent).firstOrNull;
    final terms = currentYear == null
        ? const AsyncValue<List<AcademicTerm>>.loading()
        : ref.watch(academicTermsProvider(currentYear.id));
    final scales = ref.watch(gradeScaleListNotifierProvider);

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Test' : 'New Test'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                if (_isEdit)
                  // Fixed at creation, so shown rather than offered.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${widget.assessment!.classSectionName} · ${widget.assessment!.subjectName}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _sectionId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Class', errorText: _serverError('class_section_id')),
                    items: [
                      for (final option in sections.value ?? const <ClassSectionOption>[])
                        DropdownMenuItem(value: option.id, child: Text(option.label)),
                    ],
                    onChanged: (value) => setState(() => _sectionId = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _subjectId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Subject', errorText: _serverError('subject_id')),
                    items: [
                      for (final subject in subjects.value ?? const <Subject>[])
                        DropdownMenuItem(value: subject.id, child: Text(subject.name)),
                    ],
                    onChanged: (value) => setState(() => _subjectId = value),
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<int>(
                  initialValue: _termId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Term', errorText: _serverError('academic_term_id')),
                  items: [
                    for (final term in terms.value ?? const <AcademicTerm>[])
                      DropdownMenuItem(value: term.id, child: Text(term.name)),
                  ],
                  onChanged: (value) => setState(() => _termId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<AssessmentType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Kind of test'),
                  items: [
                    for (final type in AssessmentType.values) DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? AssessmentType.classTest),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(labelText: 'Title', errorText: _serverError('title')),
                  maxLength: 150,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _maxMarksController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Out of', errorText: _serverError('max_marks')),
                        validator: (v) {
                          final parsed = double.tryParse(v?.trim() ?? '');
                          return (parsed == null || parsed <= 0) ? 'More than 0' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _passMarksController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Pass mark (optional)',
                          errorText: _serverError('pass_marks'),
                        ),
                        validator: _optionalNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _weightageController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Weight in term % (optional)',
                          errorText: _serverError('weightage'),
                        ),
                        validator: _optionalNumber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: InputDecoration(labelText: 'Date', errorText: _serverError('assessment_date')),
                          child: Text(_date == null ? 'Select a date' : DateFormat.yMMMd().format(_date!)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: _gradeScaleId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Grade scale (optional)',
                    errorText: _serverError('grade_scale_id'),
                    helperText: 'Leave empty to show marks without a grade.',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No grade')),
                    for (final scale in scales.value?.items ?? const [])
                      DropdownMenuItem<int?>(value: scale.id, child: Text(scale.name)),
                  ],
                  onChanged: (value) => setState(() => _gradeScaleId = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  static String? _optionalNumber(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final parsed = double.tryParse(text);
    return (parsed == null || parsed < 0) ? 'Number' : null;
  }
}
