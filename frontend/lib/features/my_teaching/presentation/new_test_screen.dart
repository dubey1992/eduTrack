import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/searchable_dropdown.dart';
import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../assessments/data/assessment_repository.dart';
import '../../assessments/data/models/assessment.dart';
import '../../assessments/data/models/assessment_setup.dart';
import '../application/my_teaching_providers.dart';
import '../../today/presentation/staff_words.dart';

/// Setting a class test on the phone (docs/teacher-app.md, T5): which class
/// and subject (only those the teacher teaches), a title, the kind, the day,
/// the maximum and an optional pass mark. The term is the one the day falls
/// in, and the grade scale is the school's default - the website has the
/// rest (weightage, another scale). Pops with the new test's id.
class NewTestScreen extends ConsumerWidget {
  const NewTestScreen({super.key, this.today});

  /// The day the form starts on. The school's date where the caller knows it.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.staffNewClassTest)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AsyncValueView<AssessmentSetup>(
              value: ref.watch(assessmentSetupProvider),
              onRetry: () => ref.invalidate(assessmentSetupProvider),
              data: (context, setup) => setup.classes.isEmpty
                  ? _Explain(
                      key: const Key('new-test-no-classes'),
                      title: context.l10n.staffNoClassesThisYear,
                      body: context.l10n.staffNewTestNoClassesBody,
                    )
                  : setup.terms.isEmpty
                  ? _Explain(
                      key: const Key('new-test-no-terms'),
                      title: context.l10n.staffNoTermsYet,
                      body: context.l10n.staffNoTermsYetBody,
                    )
                  : _Form(setup: setup, today: today ?? DateTime.now()),
            ),
          ),
        ),
      ),
    );
  }
}

/// Why there is nothing to fill in, and who can change that.
class _Explain extends StatelessWidget {
  const _Explain({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, size: 48, color: colors.muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.setup, required this.today});

  final AssessmentSetup setup;
  final DateTime today;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _maxMarks = TextEditingController();
  final _passMarks = TextEditingController();

  late TaughtClass _class = widget.setup.classes.first;
  AssessmentType _type = AssessmentType.classTest;
  late DateTime _date = DateTime(widget.today.year, widget.today.month, widget.today.day);
  bool _sending = false;
  bool _tried = false;
  String? _problem;

  @override
  void dispose() {
    _title.dispose();
    _maxMarks.dispose();
    _passMarks.dispose();
    super.dispose();
  }

  SetupTerm? get _term => widget.setup.termFor(_date);

  String? _checkMax(String? value) {
    final text = value?.trim() ?? '';
    final l10n = context.l10n;
    if (text.isEmpty) return l10n.staffOutOfHowMany;
    final parsed = double.tryParse(text);
    if (parsed == null) return l10n.staffEnterANumber;
    if (parsed <= 0) return l10n.staffMaxMoreThanZero;
    if (parsed > 9999) return l10n.staffMaxTooBig;
    return null;
  }

  String? _checkPass(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return context.l10n.staffEnterNumberOrBlank;
    final maximum = double.tryParse(_maxMarks.text.trim());
    if (parsed < 0 || (maximum != null && parsed > maximum)) return context.l10n.staffBetweenZeroAndMax;
    return null;
  }

  Future<void> _pickDate() async {
    final terms = widget.setup.terms;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: terms.isEmpty ? DateTime(_date.year - 1) : terms.first.startDate,
      lastDate: terms.isEmpty ? DateTime(_date.year + 1) : terms.last.endDate,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _tried = true);
    if (!_form.currentState!.validate()) return;

    final term = _term;
    if (term == null) {
      setState(() => _problem = context.l10n.staffNoTermCovers(formatDate(_date)));
      return;
    }

    setState(() {
      _sending = true;
      _problem = null;
    });

    try {
      final pass = _passMarks.text.trim();
      final created = await ref
          .read(assessmentRepositoryProvider)
          .create(
            classSectionId: _class.classSectionId,
            subjectId: _class.subjectId,
            academicTermId: term.id,
            gradeScaleId: widget.setup.defaultScale?.id,
            type: _type.apiValue,
            title: _title.text.trim(),
            maxMarks: _maxMarks.text.trim(),
            passMarks: pass.isEmpty ? null : pass,
            assessmentDate: _date,
          );
      ref.invalidate(myTestsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.staffTestSet)));
      context.pop(created.id);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(
          () => _problem = switch (failure.code) {
            'NETWORK_ERROR' => context.l10n.staffNothingSavedNoSignal,
            _ when failure.validationErrors.isNotEmpty => failure.validationErrors.values.expand((e) => e).join('\n'),
            _ => failure.localizedMessage(context),
          },
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final term = _term;
    final pass = widget.setup.passPercentage;
    final l10n = context.l10n;

    return Form(
      key: _form,
      autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_problem != null) ...[
            Container(
              key: const Key('new-test-problem'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(_problem!, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
            ),
            const SizedBox(height: 12),
          ],
          SearchableDropdown<TaughtClass>(
            key: const Key('new-test-class'),
            initialValue: _class,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.staffClassAndSubject),
            items: [
              for (final taught in widget.setup.classes)
                DropdownMenuItem(
                  value: taught,
                  child: Text(taught.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _sending ? null : (value) => setState(() => _class = value ?? _class),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('new-test-title'),
            controller: _title,
            enabled: !_sending,
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.staffTitle, hintText: l10n.staffTestTitleHint),
            validator: (value) => (value == null || value.trim().isEmpty) ? l10n.staffGiveTestTitle : null,
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<AssessmentType>(
            key: const Key('new-test-type'),
            initialValue: _type,
            decoration: InputDecoration(labelText: l10n.staffKindOfTest),
            items: [
              for (final type in AssessmentType.values)
                DropdownMenuItem(value: type, child: Text(assessmentTypeLabel(l10n, type))),
            ],
            onChanged: _sending ? null : (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('new-test-date'),
            onTap: _sending ? null : _pickDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.staffDayOfTest,
                helperText: term == null ? l10n.staffNoTermCoversDay : term.name,
                helperStyle: term == null ? TextStyle(color: colors.danger) : null,
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(formatDate(_date)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('new-test-max'),
                  controller: _maxMarks,
                  enabled: !_sending,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l10n.staffOutOfLabel),
                  validator: _checkMax,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('new-test-pass'),
                  controller: _passMarks,
                  enabled: !_sending,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.staffPassMark,
                    helperText: pass == null ? l10n.staffOptional : l10n.staffPassMarkDefault('$pass'),
                    helperMaxLines: 2,
                  ),
                  validator: _checkPass,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.setup.defaultScale != null)
            Text(
              l10n.staffGradesByScale(widget.setup.defaultScale!.name),
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('new-test-submit'),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.staffSetTest),
            ),
          ),
        ],
      ),
    );
  }
}
