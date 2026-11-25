import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/ptm_providers.dart';
import '../data/ptm_models.dart';

const ptmTitleMax = 120;
const ptmNoteMax = 300;

/// Creates a meeting day, or changes one ([meeting]): its name, date, note
/// to parents and the classes taking part.
class PtmMeetingDialog extends ConsumerStatefulWidget {
  const PtmMeetingDialog({super.key, this.meeting});

  final PtmMeeting? meeting;

  @override
  ConsumerState<PtmMeetingDialog> createState() => _PtmMeetingDialogState();
}

class _PtmMeetingDialogState extends ConsumerState<PtmMeetingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.meeting?.title);
  late final _note = TextEditingController(text: widget.meeting?.note);
  late DateTime? _date = widget.meeting?.date;
  late final Set<int> _sections = {...?widget.meeting?.classes.map((c) => c.id)};
  late int? _schoolId = widget.meeting?.schoolId;
  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  bool _triedSave = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date != null && !_date!.isBefore(today) ? _date! : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _triedSave = true);
    final valid = _formKey.currentState!.validate();
    if (!valid || _date == null || _sections.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final note = _note.text.trim();

    try {
      await ref
          .read(ptmMeetingsProvider.notifier)
          .save(
            PtmMeetingDraft(
              title: _title.text.trim(),
              date: _date!,
              note: note.isEmpty ? null : note,
              sectionIds: _sections.toList()..sort(),
              schoolId: _schoolId,
            ),
            id: widget.meeting?.id,
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(widget.meeting == null ? l10n.ptmMeetingCreated : l10n.ptmSaved)));
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.localizedMessage(context);
          _fieldErrors = {for (final e in failure.validationErrors.entries) e.key: e.value.first};
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colours = context.appColors;
    final user = ref.watch(authNotifierProvider).value;
    final picksSchool = (user?.picksSchool ?? false) && widget.meeting == null;
    final schoolId = picksSchool ? _schoolId : null;
    final options = ref.watch(classSectionPickerProvider(schoolId));
    final available = options.value ?? const <ClassSectionOption>[];

    return AlertDialog(
      title: Text(widget.meeting == null ? l10n.ptmNewMeeting : l10n.ptmEditMeeting),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const Key('ptm-form-error'),
                    style: TextStyle(color: colours.danger),
                  ),
                  const SizedBox(height: 12),
                ],
                if (picksSchool) ...[
                  SchoolPicker(
                    selected: _schoolId,
                    onChanged: (value) => setState(() {
                      _schoolId = value;
                      _sections.clear();
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  key: const Key('ptm-title'),
                  controller: _title,
                  maxLength: ptmTitleMax,
                  decoration: InputDecoration(
                    labelText: l10n.ptmTitleLabel,
                    hintText: l10n.ptmTitleHint,
                    errorText: _fieldErrors['title'],
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty ? l10n.ptmTitleRequired : null,
                ),
                const SizedBox(height: 6),
                InkWell(
                  key: const Key('ptm-date'),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.ptmDateLabel,
                      errorText:
                          _fieldErrors['meeting_date'] ?? (_triedSave && _date == null ? l10n.ptmDateRequired : null),
                      suffixIcon: const Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(_date == null ? l10n.ptmPickDate : formatDate(_date!)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('ptm-note'),
                  controller: _note,
                  maxLength: ptmNoteMax,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: l10n.ptmNoteLabel,
                    helperText: l10n.ptmNoteHelp,
                    errorText: _fieldErrors['note'],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text(l10n.ptmClassesTakingPart, style: Theme.of(context).textTheme.titleSmall)),
                    if (available.isNotEmpty)
                      TextButton(
                        key: const Key('ptm-all-classes'),
                        onPressed: () => setState(() {
                          if (_sections.length == available.length) {
                            _sections.clear();
                          } else {
                            _sections.addAll(available.map((o) => o.id));
                          }
                        }),
                        child: Text(_sections.length == available.length ? l10n.ptmClearAll : l10n.ptmSelectAll),
                      ),
                  ],
                ),
                if (options.isLoading)
                  const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
                else if (available.isEmpty)
                  Text(
                    picksSchool && _schoolId == null ? l10n.ptmChooseSchoolFirst : l10n.ptmNoClassesYet,
                    style: TextStyle(color: colours.muted),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in available)
                        FilterChip(
                          key: Key('ptm-class-option-${option.id}'),
                          label: Text(option.label),
                          selected: _sections.contains(option.id),
                          onSelected: (on) =>
                              setState(() => on ? _sections.add(option.id) : _sections.remove(option.id)),
                        ),
                    ],
                  ),
                if ((_triedSave && _sections.isEmpty) || _fieldErrors['section_ids'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _fieldErrors['section_ids'] ?? l10n.ptmClassesRequired,
                      style: TextStyle(color: colours.danger, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          key: const Key('ptm-save'),
          onPressed: _saving ? null : _save,
          child: Text(widget.meeting == null ? l10n.ptmCreate : l10n.ptmSave),
        ),
      ],
    );
  }
}
