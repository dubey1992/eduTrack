import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/searchable_dropdown.dart';
import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../auth/application/auth_notifier.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../application/my_teaching_providers.dart';
import '../application/staff_outbox.dart';
import '../data/outbox.dart';
import '../data/report_notes.dart';
import 'report_detail_screen.dart' show HodNote;

/// Which period a report is for. Everything comes from Today, which has it
/// from the server, so the form asks nothing it already knows.
class ReportPeriod {
  const ReportPeriod({
    required this.timetableEntryId,
    required this.date,
    required this.classSection,
    required this.subject,
    required this.periodNumber,
    this.subjectId,
    this.classSectionId,
  });

  final int timetableEntryId;

  /// `yyyy-MM-dd`, the school's date.
  final String date;
  final String classSection;
  final String subject;
  final int periodNumber;
  final int? subjectId;

  /// With [subjectId], what "Same as last time" looks for. Optional: an
  /// older link without it simply offers no copy.
  final int? classSectionId;
}

/// Saying what a period covered (docs/teacher-app.md, T3): the topic taught,
/// optionally the syllabus topic it ticks off, homework and remarks. The
/// same rules as the web, kept by the server: one report per period and
/// day, nothing dated ahead, and only the teacher's own periods.
class FileReportScreen extends ConsumerStatefulWidget {
  const FileReportScreen({super.key, required this.period, this.changing});

  /// Changing a report the HOD sent back, with its note (T7): what was
  /// taught, homework and remarks, sent again for review.
  FileReportScreen.change({super.key, required TeachingReport this.changing})
    : period = ReportPeriod(
        timetableEntryId: changing.timetableEntryId,
        date: changing.reportDate,
        classSection: changing.classSectionName ?? '',
        subject: changing.subjectName ?? 'Report',
        periodNumber: changing.periodNumber ?? 0,
      );

  final ReportPeriod period;
  final TeachingReport? changing;

  @override
  ConsumerState<FileReportScreen> createState() => _FileReportScreenState();
}

class _FileReportScreenState extends ConsumerState<FileReportScreen> {
  static const topicLimit = 255;
  static const noteLimit = 500;

  final _form = GlobalKey<FormState>();
  final _topic = TextEditingController();
  final _homework = TextEditingController();
  final _remarks = TextEditingController();

  int? _syllabusTopicId;
  bool _sending = false;

  /// After the first Submit, a field's message clears as soon as it is fixed.
  bool _tried = false;
  String? _problem;

  /// The teacher has not checked in today, so the school will not take the
  /// report yet (decided 2026-11-02). Today, where the check-in is, is one
  /// step back.
  bool _needsCheckIn = false;

  /// Writes the draft a moment after the last keystroke, not on every one.
  Timer? _draftTimer;

  /// Held from the start: a ref is no longer usable in dispose(), where
  /// the last draft is written.
  late final ReportNotes _notes;

  bool get _isNew => widget.changing == null;

  @override
  void initState() {
    super.initState();
    _notes = ref.read(reportNotesProvider);
    final changing = widget.changing;
    if (changing != null) {
      _topic.text = changing.topicTaught;
      _homework.text = changing.homework ?? '';
      _remarks.text = changing.remarks ?? '';
      return;
    }

    // What was typed last time this form was open for this period - kept on
    // the phone as it was typed (docs/mobile-apps-review.md, 1.6).
    unawaited(_restoreDraft());

    for (final controller in [_topic, _homework, _remarks]) {
      controller.addListener(_scheduleDraft);
    }
  }

  Future<void> _restoreDraft() async {
    final draft = await _notes.draft(widget.period.timetableEntryId, widget.period.date);
    if (draft == null || !mounted || !_words.isEmpty) return;

    _fill(draft);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(key: const Key('report-draft-restored'), content: Text(context.l10n.staffDraftIsBack)));
  }

  ReportWords get _words => ReportWords(topic: _topic.text, homework: _homework.text, remarks: _remarks.text);

  void _fill(ReportWords words) {
    _topic.text = words.topic;
    _homework.text = words.homework;
    _remarks.text = words.remarks;
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() => _notes.saveDraft(widget.period.timetableEntryId, widget.period.date, _words);

  /// "Same as last time": the teacher's last report for this class and
  /// subject, copied in to be changed where today differed.
  void _copyLast(TeachingReport last) {
    _fill(ReportWords(topic: last.topicTaught, homework: last.homework ?? '', remarks: last.remarks ?? ''));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.staffCopiedFrom(formatIsoDate(last.reportDate)))));
  }

  Future<void> _openTemplates(int subjectId) async {
    final chosen = await showModalBottomSheet<ReportWords>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _TemplatesSheet(subjectId: subjectId, current: _words, subject: widget.period.subject),
    );
    if (chosen != null && mounted) _fill(chosen);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // A keystroke inside the last moment still makes the draft.
    if (_isNew && !_filed) unawaited(_saveDraft());
    _topic.dispose();
    _homework.dispose();
    _remarks.dispose();
    super.dispose();
  }

  /// Set once the report is in, so leaving does not write it back as a draft.
  bool _filed = false;

  String? _trimmedOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _tried = true);
    if (!_form.currentState!.validate()) return;

    setState(() {
      _sending = true;
      _problem = null;
      _needsCheckIn = false;
    });

    try {
      final changing = widget.changing;
      if (changing != null) {
        await ref
            .read(resubmitReportProvider)
            .call(
              changing.id,
              topicTaught: _topic.text.trim(),
              homework: _trimmedOrNull(_homework),
              remarks: _trimmedOrNull(_remarks),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.staffSentAgainForReview)));
        Navigator.of(context).pop(true);
        return;
      }

      await ref
          .read(fileReportProvider)
          .call(
            timetableEntryId: widget.period.timetableEntryId,
            reportDate: widget.period.date,
            topicTaught: _topic.text.trim(),
            syllabusTopicId: _syllabusTopicId,
            homework: _trimmedOrNull(_homework),
            remarks: _trimmedOrNull(_remarks),
          );
      _filed = true;
      _draftTimer?.cancel();
      await _notes.forgetDraft(widget.period.timetableEntryId, widget.period.date);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.staffReportFiledDone)));
      context.pop(true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      // No signal: kept on the phone and sent when there is some (2.1). A
      // change for the HOD is not - it is answering a person, now.
      if (failure.code == 'NETWORK_ERROR' && _isNew) {
        await _keepForLater();
        return;
      }
      if (mounted) {
        setState(() {
          _problem = _say(failure);
          _needsCheckIn = failure.code == 'CHECK_IN_REQUIRED';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Sent from this phone earlier and turned down: why, above the words
  /// (2.1). Watched, so it shows whenever the outbox has been read.
  Widget? _refusal() {
    final key = OutboxItem.reportKey(widget.period.timetableEntryId, widget.period.date);
    final refused = ref.watch(staffOutboxProvider).where((i) => i.key == key && i.refusal != null).firstOrNull;
    if (refused == null) return null;

    final colors = context.appColors;
    return Container(
      key: const Key('report-refused'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(
        context.l10n.staffNotSentReason('${refused.refusal}'),
        style: TextStyle(color: colors.onDangerContainer, height: 1.35),
      ),
    );
  }

  Future<void> _keepForLater() async {
    final period = widget.period;
    final l10n = context.l10n;
    final me = (await ref.read(authNotifierProvider.future))?.id;
    if (me == null) return;

    await ref
        .read(staffOutboxProvider.notifier)
        .add(
          OutboxItem(
            kind: OutboxKind.report,
            key: OutboxItem.reportKey(period.timetableEntryId, period.date),
            userId: me,
            label: l10n.staffOutboxReportLabel(period.subject, period.classSection, period.periodNumber),
            payload: {
              'timetable_entry_id': period.timetableEntryId,
              'report_date': period.date,
              'topic_taught': _topic.text.trim(),
              'syllabus_topic_id': _syllabusTopicId,
              'homework': _trimmedOrNull(_homework),
              'remarks': _trimmedOrNull(_remarks),
            },
            savedAt: DateTime.now(),
          ),
        );
    // The outbox has the words now; the draft would only show them twice.
    _filed = true;
    _draftTimer?.cancel();
    await _notes.forgetDraft(period.timetableEntryId, period.date);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(key: const Key('report-kept-for-later'), content: Text(l10n.staffReportKeptForLater)));
    context.pop(true);
  }

  /// The server's refusals in a teacher's words; anything else as it came.
  String _say(Failure failure) => switch (failure.code) {
    'TEACHING_REPORT_ALREADY_SUBMITTED' => context.l10n.staffReportAlreadyFiled(formatIsoDate(widget.period.date)),
    'NETWORK_ERROR' => context.l10n.staffNothingSentNoSignal,
    'FORBIDDEN' => context.l10n.staffPeriodNoLongerYours,
    'TEACHING_REPORT_NOT_RETURNED' => context.l10n.staffReportNoLongerReturned,
    'CHECK_IN_REQUIRED' => context.l10n.staffCheckInFirst,
    _ => failure.localizedMessage(context),
  };

  /// Same as last time, and the subject's templates - each only where the
  /// period says enough to find them.
  Widget _helpers(ReportPeriod period) {
    final classSectionId = period.classSectionId;
    final subjectId = period.subjectId;
    final last = classSectionId == null || subjectId == null
        ? null
        : ref
              .watch(lastReportProvider((classSectionId: classSectionId, subjectId: subjectId, before: period.date)))
              .value;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (last != null)
          OutlinedButton.icon(
            key: const Key('report-same-as-last'),
            onPressed: _sending ? null : () => _copyLast(last),
            icon: const Icon(Icons.content_copy, size: 18),
            label: Text(context.l10n.staffSameAs(formatIsoDate(last.reportDate))),
          ),
        if (subjectId != null)
          OutlinedButton.icon(
            key: const Key('report-templates'),
            onPressed: _sending ? null : () => _openTemplates(subjectId),
            icon: const Icon(Icons.bookmarks_outlined, size: 18),
            label: Text(context.l10n.staffTemplates),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final colors = context.appColors;
    final l10n = context.l10n;
    // A report sent back with no subject: said in the person's language.
    final subject = widget.changing != null && widget.changing!.subjectName == null ? l10n.staffReport : period.subject;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.changing == null ? l10n.staffTeachingReport : l10n.staffChangeTheReport),
            Text(
              '$subject · ${period.classSection} · ${l10n.staffPeriodNumber(period.periodNumber)}',
              style: TextStyle(fontSize: 13, color: colors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _form,
              autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(formatIsoDate(period.date), style: TextStyle(color: colors.muted)),
                  const SizedBox(height: 12),
                  if (_problem == null && _isNew) ?_refusal(),
                  if (_problem != null) ...[
                    Container(
                      key: const Key('report-problem'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text(_problem!, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
                    ),
                    if (_needsCheckIn) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          key: const Key('report-go-check-in'),
                          onPressed: () => context.pop(false),
                          icon: const Icon(Icons.login, size: 18),
                          label: Text(l10n.staffBackToTodayToCheckIn),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  if (_isNew) ...[_helpers(period), const SizedBox(height: 8)],
                  TextFormField(
                    key: const Key('report-topic'),
                    controller: _topic,
                    enabled: !_sending,
                    maxLines: 3,
                    minLines: 2,
                    maxLength: topicLimit,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: l10n.staffWhatWasTaught,
                      hintText: l10n.staffWhatWasTaughtHint,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? l10n.staffSayWhatWasTaught : null,
                  ),
                  const SizedBox(height: 8),
                  if (widget.changing?.reviewNote != null) ...[
                    HodNote(report: widget.changing!),
                    const SizedBox(height: 12),
                  ],
                  if (period.subjectId != null && widget.changing == null)
                    _SyllabusTopicChoice(
                      subjectId: period.subjectId!,
                      timetableEntryId: period.timetableEntryId,
                      value: _syllabusTopicId,
                      enabled: !_sending,
                      onChanged: (id) => setState(() => _syllabusTopicId = id),
                    ),
                  TextFormField(
                    key: const Key('report-homework'),
                    controller: _homework,
                    enabled: !_sending,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: noteLimit,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: l10n.staffHomeworkOptional),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('report-remarks'),
                    controller: _remarks,
                    enabled: !_sending,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: noteLimit,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: l10n.staffRemarksOptional),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const Key('report-submit'),
                      onPressed: _sending ? null : _submit,
                      child: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(widget.changing == null ? l10n.staffFileReport : l10n.staffSendAgain),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The syllabus topics of the period's subject. Picking one ticks it off for
/// the class when the report is filed. Optional: a revision period or a test
/// belongs to no chapter. A syllabus that cannot be loaded must not stop a
/// report, so then the choice is simply absent - with a line saying so.
class _SyllabusTopicChoice extends ConsumerWidget {
  const _SyllabusTopicChoice({
    required this.subjectId,
    required this.timetableEntryId,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int subjectId;
  final int timetableEntryId;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return ref
        .watch(subjectTopicsProvider((subjectId: subjectId, timetableEntryId: timetableEntryId)))
        .when(
          loading: () => const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
          error: (_, _) => Padding(
            key: const Key('report-topics-unavailable'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(context.l10n.staffSyllabusUnavailable, style: TextStyle(color: colors.muted, fontSize: 13)),
          ),
          data: (topics) {
            if (topics.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SearchableDropdown<int?>(
                key: const Key('report-syllabus-topic'),
                initialValue: value,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.staffSyllabusTopicOptional,
                  helperText: context.l10n.staffSyllabusTopicHelper,
                ),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(context.l10n.staffNotASyllabusTopic)),
                  for (final topic in topics)
                    DropdownMenuItem<int?>(
                      value: topic.id,
                      child: Text(topic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: enabled ? onChanged : null,
              ),
            );
          },
        );
  }
}

/// The subject's saved templates: tap one to fill the form, or keep what is
/// typed now as a new one. On this phone only.
class _TemplatesSheet extends ConsumerStatefulWidget {
  const _TemplatesSheet({required this.subjectId, required this.current, required this.subject});

  final int subjectId;
  final ReportWords current;
  final String subject;

  @override
  ConsumerState<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends ConsumerState<_TemplatesSheet> {
  List<ReportWords>? _templates;

  ReportNotes get _notes => ref.read(reportNotesProvider);

  @override
  void initState() {
    super.initState();
    _notes.templates(widget.subjectId).then((found) {
      if (mounted) setState(() => _templates = found);
    });
  }

  Future<void> _saveCurrent() async {
    final kept = await _notes.saveTemplate(widget.subjectId, widget.current);
    if (mounted) setState(() => _templates = kept);
  }

  Future<void> _delete(ReportWords template) async {
    final kept = await _notes.deleteTemplate(widget.subjectId, template.topic);
    if (mounted) setState(() => _templates = kept);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final templates = _templates;
    final canSave = widget.current.topic.trim().isNotEmpty;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          key: const Key('report-templates-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(l10n.staffSubjectTemplates(widget.subject), style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.staffTemplatesHint, style: TextStyle(color: colors.muted)),
            ),
            if (templates == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (templates.isEmpty)
              Padding(
                key: const Key('report-templates-empty'),
                padding: const EdgeInsets.all(16),
                child: Text(l10n.staffTemplatesEmpty, style: TextStyle(color: colors.muted)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (index, template) in templates.indexed)
                      ListTile(
                        key: Key('report-template-$index'),
                        title: Text(template.topic, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: template.homework.isEmpty
                            ? null
                            : Text(
                                l10n.staffHomeworkLine(template.homework),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => Navigator.of(context).pop(template),
                        trailing: IconButton(
                          key: Key('report-template-delete-$index'),
                          tooltip: l10n.staffDeleteTemplate,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(template),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                key: const Key('report-template-save'),
                onPressed: canSave ? _saveCurrent : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(canSave ? l10n.staffSaveAsTemplate : l10n.staffTypeToSaveTemplate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
