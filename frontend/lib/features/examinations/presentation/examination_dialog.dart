import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../academic_years/application/academic_term_notifier.dart';
import '../../academic_years/application/viewed_year.dart';
import '../../academic_years/data/models/academic_term.dart';
import '../application/examination_providers.dart';
import '../data/examination_repository.dart';
import '../data/models/examination.dart';

/// An exam's own details: its name and term, the centre, the reporting
/// time, the instructions printed on every card, the card's look, and
/// whether overdue fees hold a card back (docs/examinations.md).
///
/// A new exam belongs to the year in view. Closes with the saved exam.
class ExaminationDialog extends ConsumerStatefulWidget {
  const ExaminationDialog({super.key, this.exam});

  final Examination? exam;

  @override
  ConsumerState<ExaminationDialog> createState() => _ExaminationDialogState();
}

class _ExaminationDialogState extends ConsumerState<ExaminationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.exam?.name ?? '');
  late final _centre = TextEditingController(text: widget.exam?.centre ?? '');
  late final _instructions = TextEditingController(
    text:
        widget.exam?.instructions ??
        'Carry this admit card to every examination.\n'
            'Arrive at the examination centre before the reporting time.\n'
            'Follow the school rules and the invigilator\'s instructions.',
  );
  late int? _termId = widget.exam?.academicTermId;
  late String? _reportingTime = widget.exam?.reportingTime;
  late ExamCardStyle _style = widget.exam?.cardStyle ?? ExamCardStyle.classic;
  late bool _blockOnFees = widget.exam?.blockOnFeeDues ?? false;

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.exam != null;

  @override
  void dispose() {
    _name.dispose();
    _centre.dispose();
    _instructions.dispose();
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  Future<void> _pickReportingTime() async {
    final current = _reportingTime?.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 8, minute: 30)
          : TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])),
    );
    if (picked != null) setState(() => _reportingTime = hhmm(picked));
  }

  Future<void> _submit(int? yearId) async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (!_isEdit && yearId == null) {
      setState(() => _error = 'Choose an academic year in the top bar first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final fields = <String, dynamic>{
      if (!_isEdit) 'academic_year_id': yearId,
      'name': _name.text.trim(),
      'academic_term_id': _termId,
      'centre': _centre.text.trim(),
      'reporting_time': _reportingTime,
      'instructions': _instructions.text.trim(),
      'card_style': _style.apiValue,
      'block_on_fee_dues': _blockOnFees,
    };

    try {
      final Examination saved;
      if (_isEdit) {
        await ref.read(examinationProvider(widget.exam!.id).notifier).updateDetails(fields);
        saved = ref.read(examinationProvider(widget.exam!.id)).value!;
      } else {
        saved = await ref.read(examinationRepositoryProvider).create(fields);
        ref.invalidate(examinationListProvider);
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(saved);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Exam saved.' : 'Exam created. Add its date sheet next.')),
      );
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          _error = _fieldErrors.isEmpty ? failure.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(viewedYearProvider).value;
    final yearId = widget.exam?.academicYearId ?? year?.id;
    final terms = yearId == null
        ? const AsyncValue<List<AcademicTerm>>.data([])
        : ref.watch(academicTermsProvider(yearId));
    final colors = context.appColors;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit exam' : 'New exam'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const Key('exam-dialog-error'),
                    style: TextStyle(color: colors.danger),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Academic year: ${widget.exam?.academicYearName ?? year?.name ?? 'none chosen'}',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('exam-name'),
                  controller: _name,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Exam name (e.g. Half-Yearly Examination)',
                    errorText: _serverError('name'),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name the exam.' : null,
                ),
                DropdownButtonFormField<int?>(
                  key: const Key('exam-term'),
                  initialValue: _termId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Term (optional)',
                    errorText: _serverError('academic_term_id'),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No term')),
                    for (final term in terms.value ?? const <AcademicTerm>[])
                      DropdownMenuItem<int?>(value: term.id, child: Text(term.name)),
                  ],
                  onChanged: (value) => setState(() => _termId = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('exam-centre'),
                  controller: _centre,
                  maxLength: 150,
                  decoration: InputDecoration(
                    labelText: 'Examination centre (optional)',
                    errorText: _serverError('centre'),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _reportingTime == null
                            ? 'No reporting time'
                            : 'Reporting time: ${formatClock(_reportingTime!)}',
                      ),
                    ),
                    TextButton(
                      key: const Key('exam-reporting-time'),
                      onPressed: _pickReportingTime,
                      child: Text(_reportingTime == null ? 'Set time' : 'Change'),
                    ),
                    if (_reportingTime != null)
                      TextButton(onPressed: () => setState(() => _reportingTime = null), child: const Text('Clear')),
                  ],
                ),
                if (_serverError('reporting_time') != null)
                  Text(_serverError('reporting_time')!, style: TextStyle(color: colors.danger, fontSize: 12)),
                const SizedBox(height: 8),
                DropdownButtonFormField<ExamCardStyle>(
                  key: const Key('exam-style'),
                  initialValue: _style,
                  decoration: const InputDecoration(labelText: 'Card look'),
                  items: [
                    for (final style in ExamCardStyle.values) DropdownMenuItem(value: style, child: Text(style.label)),
                  ],
                  onChanged: (value) => setState(() => _style = value ?? ExamCardStyle.classic),
                ),
                SwitchListTile(
                  key: const Key('exam-block-fees'),
                  contentPadding: EdgeInsets.zero,
                  value: _blockOnFees,
                  onChanged: (value) => setState(() => _blockOnFees = value),
                  title: const Text('Hold the card while fees are overdue'),
                  subtitle: const Text('You can still let a named student through.'),
                ),
                TextFormField(
                  key: const Key('exam-instructions'),
                  controller: _instructions,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: 'Instructions on the card (one per line)',
                    errorText: _serverError('instructions'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('exam-save'),
          onPressed: _saving ? null : () => _submit(yearId),
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// "08:30" from a picked time.
String hhmm(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
