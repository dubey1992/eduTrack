import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/staff_outbox.dart';
import '../data/outbox.dart';
import '../../auth/application/auth_notifier.dart';
import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../assessments/application/assessment_sheet_notifier.dart';
import '../../assessments/data/assessment_repository.dart';
import '../../assessments/data/models/assessment.dart';
import '../../assessments/data/models/assessment_sheet.dart';
import '../application/my_teaching_providers.dart';

/// Entering a class test's marks on the phone (docs/teacher-app.md, T5).
///
/// The class as a list: each student with a number box and an Absent
/// switch, Next on the keyboard moving down the class. The whole sheet is
/// saved in one go, as on the web - a half-saved sheet is worse than an
/// unsaved one. Published, it is read-only with the grades.
class MarksEntryScreen extends ConsumerWidget {
  const MarksEntryScreen({super.key, required this.assessmentId});

  final int assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(assessmentSheetProvider(assessmentId));

    if (sheet.hasValue) return _Sheet(assessmentId: assessmentId, initial: sheet.requireValue);

    // Loading, or failed with Retry: under a plain app bar of its own.
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.staffTabMarks)),
      body: SafeArea(
        child: AsyncValueView<AssessmentSheet>(
          value: sheet,
          onRetry: () => ref.read(assessmentSheetProvider(assessmentId).notifier).refresh(),
          data: (context, value) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.assessmentId, required this.initial});

  final int assessmentId;
  final AssessmentSheet initial;

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  final Map<int, TextEditingController> _boxes = {};
  final Map<int, FocusNode> _focus = {};

  /// The server's objections, by student.
  Map<int, String> _rowErrors = {};
  bool _busy = false;
  String? _problem;

  AssessmentSheetNotifier get _notifier => ref.read(assessmentSheetProvider(widget.assessmentId).notifier);

  @override
  void initState() {
    super.initState();
    _fill(widget.initial);
  }

  @override
  void dispose() {
    for (final box in _boxes.values) {
      box.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Sets every box to what the sheet says - on opening and after a save,
  /// when the server has tidied the numbers.
  void _fill(AssessmentSheet sheet) {
    for (final entry in sheet.entries) {
      final box = _boxes.putIfAbsent(entry.studentId, TextEditingController.new);
      box.text = entry.marksForEditing;
      _focus.putIfAbsent(entry.studentId, FocusNode.new);
    }
  }

  double get _max => double.tryParse(widget.initial.assessment.maxMarks) ?? 0;

  /// What is wrong with a typed mark, before anything is sent.
  String? _check(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null) return context.l10n.staffNotANumber;
    if (parsed < 0 || parsed > _max) {
      return context.l10n.staffOutOfMarks('${Assessment.tidyMarks(widget.initial.assessment.maxMarks)}');
    }
    return null;
  }

  /// How many typed marks would be refused - shown beside the disabled Save,
  /// since the row at fault may be far up the list.
  int _typingErrors(AssessmentSheet sheet) =>
      sheet.entries.where((entry) => !entry.isAbsent && _check(_boxes[entry.studentId]?.text ?? '') != null).length;

  bool _anyTypingError(AssessmentSheet sheet) => _typingErrors(sheet) > 0;

  Future<void> _save(AssessmentSheet sheet) async {
    if (_busy || _anyTypingError(sheet)) return;
    FocusScope.of(context).unfocus();
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _problem = null;
      _rowErrors = {};
    });

    try {
      await _notifier.save();
      final saved = ref.read(assessmentSheetProvider(widget.assessmentId)).value;
      if (saved != null) _fill(saved);
      ref.invalidate(myTestsProvider);
      // Floated above the Save and Publish bar, so Publish can be tapped at once.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.staffMarksSaved),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
            ),
          );
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (!mounted) return;
      setState(() {
        _rowErrors = _byStudent(sheet, failure.validationErrors);
        _problem = switch (failure.code) {
          'NETWORK_ERROR' => l10n.staffMarksKeptForLater,
          'ASSESSMENT_PUBLISHED' => l10n.staffTestAlreadyPublished,
          _ when _rowErrors.isNotEmpty => l10n.staffSomeMarksRefused,
          _ => failure.localizedMessage(context),
        };
      });
      if (failure.code == 'ASSESSMENT_PUBLISHED') await _notifier.reload();
      // Kept, and sent when there is signal (2.1): the newest marks replace
      // any saved before them.
      if (failure.code == 'NETWORK_ERROR') await _keepForLater(sheet, l10n);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepForLater(AssessmentSheet sheet, AppLocalizations l10n) async {
    final me = (await ref.read(authNotifierProvider.future))?.id;
    if (me == null) return;

    await ref
        .read(staffOutboxProvider.notifier)
        .add(
          OutboxItem(
            kind: OutboxKind.marks,
            key: OutboxItem.marksKey(widget.assessmentId),
            userId: me,
            label: l10n.staffOutboxMarksLabel(sheet.assessment.title),
            payload: {
              'assessment_id': widget.assessmentId,
              'marks': [for (final entry in sheet.entries) entry.toJson()],
            },
            savedAt: DateTime.now(),
          ),
        );
  }

  /// `marks.3.marks_obtained` -> the fourth student on the sheet.
  Map<int, String> _byStudent(AssessmentSheet sheet, Map<String, List<String>> errors) {
    final found = <int, String>{};
    for (final entry in errors.entries) {
      final match = RegExp(r'^marks\.(\d+)\.').firstMatch(entry.key);
      if (match == null) continue;
      final index = int.parse(match.group(1)!);
      if (index < sheet.entries.length) found[sheet.entries[index].studentId] = entry.value.join(' ');
    }
    return found;
  }

  Future<void> _publish(AssessmentSheet sheet) async {
    // Publishing tells families the marks the school has - not marks still
    // on this phone (2.1).
    if (ref.read(staffOutboxProvider.notifier).waitingFor(OutboxItem.marksKey(widget.assessmentId)) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(key: const Key('marks-still-waiting'), content: Text(context.l10n.staffMarksStillWaiting)),
      );
      return;
    }
    final test = sheet.assessment;
    final sitting = sheet.entries.where((entry) => !entry.isAbsent).length;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('marks-publish-confirm'),
        title: Text(l10n.staffPublishResultsQ),
        content: Text(test.willTellGuardians ? l10n.staffPublishFirstBody(sitting) : l10n.staffPublishAgainBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.staffNotYet)),
          FilledButton(
            key: const Key('marks-publish-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.staffPublish),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref.read(assessmentRepositoryProvider).publish(widget.assessmentId);
      ref.invalidate(myTestsProvider);
      await _notifier.reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.staffResultsPublished)));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(
          () => _problem = failure.code == 'NETWORK_ERROR'
              ? l10n.staffNothingPublishedNoSignal
              : failure.localizedMessage(context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _leave() async {
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('marks-leave-confirm'),
        title: Text(l10n.staffLeaveWithoutSavingQ),
        content: Text(l10n.staffLeaveWithoutSavingBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.staffKeepEntering)),
          TextButton(
            key: const Key('marks-leave-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.staffLeaveScreen),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final sheet = ref.watch(assessmentSheetProvider(widget.assessmentId)).value ?? widget.initial;
    final test = sheet.assessment;
    final editable = test.isDraft;
    final dirty = _notifier.isDirty;
    final colors = context.appColors;
    final l10n = context.l10n;

    return PopScope(
      canPop: !dirty || !editable,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _leave() && context.mounted) {
          // Throws the typing away: the next visit reads the server again.
          ref.invalidate(assessmentSheetProvider(widget.assessmentId));
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(test.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${test.subjectName} · ${test.classSectionName} · ${formatDate(test.assessmentDate)}',
                style: TextStyle(fontSize: 13, color: colors.muted, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  _Summary(sheet: sheet),
                  if (!editable)
                    _Banner(
                      key: const Key('marks-published'),
                      text: l10n.staffMarksPublishedBanner,
                      background: colors.successContainer,
                      foreground: colors.onSuccessContainer,
                    ),
                  if (_problem != null)
                    _Banner(
                      key: const Key('marks-problem'),
                      text: _problem!,
                      background: colors.dangerContainer,
                      foreground: colors.onDangerContainer,
                    ),
                  Expanded(
                    child: sheet.entries.isEmpty
                        ? Center(
                            key: const Key('marks-no-students'),
                            child: Text(l10n.staffNobodyToMark, style: TextStyle(color: colors.muted)),
                          )
                        : ListView.separated(
                            key: const Key('marks-list'),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            itemCount: sheet.entries.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = sheet.entries[index];
                              final next = index + 1 < sheet.entries.length
                                  ? _focus[sheet.entries[index + 1].studentId]
                                  : null;
                              return editable
                                  ? _EditableRow(
                                      entry: entry,
                                      box: _boxes[entry.studentId]!,
                                      focus: _focus[entry.studentId]!,
                                      next: next,
                                      enabled: !_busy,
                                      typingError: entry.isAbsent ? null : _check(_boxes[entry.studentId]!.text),
                                      serverError: _rowErrors[entry.studentId],
                                      onMark: (text) {
                                        setState(() => _rowErrors.remove(entry.studentId));
                                        _notifier.setMark(entry.studentId, text.trim());
                                      },
                                      onAbsent: (absent) {
                                        if (absent) _boxes[entry.studentId]!.clear();
                                        setState(() => _rowErrors.remove(entry.studentId));
                                        _notifier.setAbsent(entry.studentId, absent);
                                      },
                                    )
                                  : _PublishedRow(entry: entry, maxMarks: test.maxMarksLabel);
                            },
                          ),
                  ),
                  if (editable)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(top: BorderSide(color: colors.muted.withValues(alpha: 0.2))),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_anyTypingError(sheet))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                l10n.staffMarksFixFirst(_typingErrors(sheet)),
                                key: const Key('marks-fix-first'),
                                style: TextStyle(color: colors.danger),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    key: const Key('marks-save'),
                                    onPressed: _busy || !dirty || _anyTypingError(sheet) ? null : () => _save(sheet),
                                    child: _busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Text(dirty ? l10n.staffSaveMarks : l10n.staffSaved),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  key: const Key('marks-publish'),
                                  // Saved first, and everyone marked: the server
                                  // refuses anything less, so the button does too.
                                  onPressed: _busy || dirty || !sheet.isComplete ? null : () => _publish(sheet),
                                  child: Text(l10n.staffPublish),
                                ),
                              ),
                            ],
                          ),
                        ],
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

class _Summary extends StatelessWidget {
  const _Summary({required this.sheet});

  final AssessmentSheet sheet;

  @override
  Widget build(BuildContext context) {
    final test = sheet.assessment;
    final colors = context.appColors;
    final left = sheet.entries.length - sheet.markedCount;
    final pass = test.passMarks == null ? null : Assessment.tidyMarks(test.passMarks);
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.staffMarkedCount(sheet.markedCount, sheet.entries.length),
              key: const Key('marks-count'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            [
              l10n.staffOutOfMarks(test.maxMarksLabel),
              if (pass != null) l10n.staffPassMarks(pass),
              if (left > 0 && test.isDraft) l10n.staffLeft(left),
            ].join(' · '),
            style: TextStyle(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, required this.background, required this.foreground});

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(color: foreground, height: 1.35)),
  );
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    required this.entry,
    required this.box,
    required this.focus,
    required this.next,
    required this.enabled,
    required this.typingError,
    required this.serverError,
    required this.onMark,
    required this.onAbsent,
  });

  final SheetEntry entry;
  final TextEditingController box;
  final FocusNode focus;
  final FocusNode? next;
  final bool enabled;
  final String? typingError;
  final String? serverError;
  final ValueChanged<String> onMark;
  final ValueChanged<bool> onAbsent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final error = typingError ?? serverError;

    return Card(
      key: Key('marks-row-${entry.studentId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.studentName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(
                    entry.rollNumber == null ? entry.admissionNumber : l10n.staffRoll('${entry.rollNumber}'),
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                key: Key('marks-box-${entry.studentId}'),
                controller: box,
                focusNode: focus,
                enabled: enabled && !entry.isAbsent,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textInputAction: next == null ? TextInputAction.done : TextInputAction.next,
                onSubmitted: (_) => next?.requestFocus(),
                onChanged: onMark,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: entry.isAbsent ? l10n.staffAbsent : '-',
                  errorText: error,
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Column(
              children: [
                Switch(
                  key: Key('marks-absent-${entry.studentId}'),
                  value: entry.isAbsent,
                  onChanged: enabled ? onAbsent : null,
                ),
                Text(l10n.staffAbsent, style: TextStyle(fontSize: 11, color: colors.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedRow extends StatelessWidget {
  const _PublishedRow({required this.entry, required this.maxMarks});

  final SheetEntry entry;
  final String maxMarks;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    return Card(
      key: Key('marks-row-${entry.studentId}'),
      child: ListTile(
        title: Text(entry.studentName),
        subtitle: Text(entry.rollNumber == null ? entry.admissionNumber : l10n.staffRoll('${entry.rollNumber}')),
        trailing: entry.isAbsent
            ? StatusBadge(label: l10n.staffAbsent, tone: BadgeTone.neutral)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${entry.marksForEditing} / $maxMarks', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (entry.grade != null) ...[
                    const SizedBox(width: 8),
                    StatusBadge(
                      label: entry.grade!,
                      tone: entry.passed == false ? BadgeTone.danger : BadgeTone.success,
                    ),
                  ] else if (entry.passed == false) ...[
                    const SizedBox(width: 8),
                    Text(l10n.staffBelowPass, style: TextStyle(color: colors.danger, fontSize: 12)),
                  ],
                ],
              ),
      ),
    );
  }
}
