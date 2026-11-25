import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../assessments/data/models/assessment.dart';
import '../../assessments/data/models/assessment_sheet.dart';
import '../application/marks_reading.dart';

/// Shows what was read by voice or from a photo, for the teacher to check
/// and correct (docs/mobile-apps-review.md, M12, 1.7).
///
/// Returns the marks to put on the sheet, by student - only the students
/// that ended up with a mark or Absent - or null when the teacher cancels.
/// Nothing reaches the sheet from here: the sheet's own screen types the
/// confirmed marks into its boxes, and saving stays its own Save.
Future<Map<int, ReadMark>?> showMarksReview(
  BuildContext context, {
  required AssessmentSheet sheet,
  required MarksReading reading,
}) {
  return showDialog<Map<int, ReadMark>>(
    context: context,
    builder: (context) => MarksReviewDialog(sheet: sheet, reading: reading),
  );
}

class MarksReviewDialog extends StatefulWidget {
  const MarksReviewDialog({super.key, required this.sheet, required this.reading});

  final AssessmentSheet sheet;
  final MarksReading reading;

  @override
  State<MarksReviewDialog> createState() => _MarksReviewDialogState();
}

class _MarksReviewDialogState extends State<MarksReviewDialog> {
  final Map<int, TextEditingController> _boxes = {};
  final Set<int> _absent = {};

  double get _max => double.tryParse(widget.sheet.assessment.maxMarks) ?? 0;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.sheet.entries) {
      final read = widget.reading.byStudent[entry.studentId];
      _boxes[entry.studentId] = TextEditingController(text: read?.marks ?? '');
      if (read?.isAbsent ?? false) _absent.add(entry.studentId);
    }
  }

  @override
  void dispose() {
    for (final box in _boxes.values) {
      box.dispose();
    }
    super.dispose();
  }

  /// The students that end up with something: a mark typed or read, or Absent.
  Map<int, ReadMark> _confirmed() {
    return {
      for (final entry in widget.sheet.entries)
        if (_absent.contains(entry.studentId))
          entry.studentId: const ReadMark.absent()
        else if (_boxes[entry.studentId]!.text.trim().isNotEmpty)
          entry.studentId: ReadMark.mark(_boxes[entry.studentId]!.text.trim()),
    };
  }

  String? _error(String text) {
    final l10n = context.l10n;
    return switch (checkMark(text, _max)) {
      MarkProblem.notANumber => l10n.staffNotANumber,
      MarkProblem.outOfRange => l10n.staffOutOfMarks('${Assessment.tidyMarks(widget.sheet.assessment.maxMarks)}'),
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final issues = widget.reading.issues;

    return Dialog.fullscreen(
      key: const Key('marks-review'),
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false, title: Text(l10n.staffMarksReviewTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      key: const Key('marks-review-list'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Text(l10n.staffMarksReviewHint, style: TextStyle(color: colors.muted, height: 1.35)),
                        ),
                        if (issues.isNotEmpty) _Issues(issues: issues),
                        for (final entry in widget.sheet.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ReviewRow(
                              entry: entry,
                              read: widget.reading.byStudent[entry.studentId],
                              box: _boxes[entry.studentId]!,
                              absent: _absent.contains(entry.studentId),
                              error: _absent.contains(entry.studentId) ? null : _error(_boxes[entry.studentId]!.text),
                              onChanged: () => setState(() {}),
                              onAbsent: (absent) => setState(() {
                                if (absent) {
                                  _absent.add(entry.studentId);
                                  _boxes[entry.studentId]!.clear();
                                } else {
                                  _absent.remove(entry.studentId);
                                }
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(top: BorderSide(color: colors.muted.withValues(alpha: 0.2))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            // A minimum, not a fixed height: the label grows with large text (M11, 3.4).
                            constraints: const BoxConstraints(minHeight: 48),
                            child: OutlinedButton(
                              key: const Key('marks-review-cancel'),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(l10n.staffMarksReviewCancel),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: FilledButton(
                              key: const Key('marks-review-confirm'),
                              onPressed: () => Navigator.of(context).pop(_confirmed()),
                              child: Text(l10n.staffMarksReviewConfirm),
                            ),
                          ),
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

/// What was read but could not be put against anybody.
class _Issues extends StatelessWidget {
  const _Issues({required this.issues});

  final List<ReadIssue> issues;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;

    return Container(
      key: const Key('marks-review-issues'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.warningContainer, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.staffMarksNotPlaced,
            style: TextStyle(color: colors.onWarningContainer, fontWeight: FontWeight.w700),
          ),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(switch (issue.kind) {
                      ReadIssueKind.unknownRoll => l10n.staffMarksIssueUnknownRoll(issue.roll ?? ''),
                      ReadIssueKind.extraValue => l10n.staffMarksIssueExtra,
                      ReadIssueKind.readTwice => l10n.staffMarksIssueReadTwice(issue.roll ?? ''),
                      ReadIssueKind.unreadable => l10n.staffMarksIssueUnreadable,
                    }, style: TextStyle(color: colors.onWarningContainer)),
                  ),
                  if (issue.value != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _display(context, issue.value!),
                      style: TextStyle(color: colors.onWarningContainer, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _display(BuildContext context, ReadMark mark) {
    if (mark.isAbsent) return context.l10n.staffAbsent;
    return mark.marks ?? '"${mark.unreadable}"';
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.entry,
    required this.read,
    required this.box,
    required this.absent,
    required this.error,
    required this.onChanged,
    required this.onAbsent,
  });

  final SheetEntry entry;
  final ReadMark? read;
  final TextEditingController box;
  final bool absent;
  final String? error;
  final VoidCallback onChanged;
  final ValueChanged<bool> onAbsent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final unreadable = read?.isUnreadable ?? false;
    final blank = box.text.trim().isEmpty && !absent;

    // Over the maximum or not a number: red. Seen but not readable: amber.
    final Color? tint = error != null
        ? colors.dangerContainer
        : unreadable && blank
        ? colors.warningContainer
        : null;

    final String? note = unreadable && blank
        ? (read!.unreadable!.isEmpty ? l10n.staffMarksNoMarkRead : l10n.staffMarksCouldNotRead(read!.unreadable!))
        : read == null && blank
        ? l10n.staffMarksNotRead
        : null;

    return Card(
      key: Key('marks-review-row-${entry.studentId}'),
      color: tint,
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
                  if (note != null)
                    Text(
                      note,
                      key: Key('marks-review-note-${entry.studentId}'),
                      style: TextStyle(
                        color: unreadable ? colors.onWarningContainer : colors.muted,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                key: Key('marks-review-box-${entry.studentId}'),
                controller: box,
                enabled: !absent,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: absent ? l10n.staffAbsent : '-',
                  errorText: error,
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // One node for a screen reader: "Absent, switch" (M11, 3.4).
            MergeSemantics(
              child: Column(
                children: [
                  Switch(key: Key('marks-review-absent-${entry.studentId}'), value: absent, onChanged: onAbsent),
                  Text(l10n.staffAbsent, style: TextStyle(fontSize: 11, color: colors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
