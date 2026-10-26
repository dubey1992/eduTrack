import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../application/my_teaching_providers.dart';

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
  });

  final int timetableEntryId;

  /// `yyyy-MM-dd`, the school's date.
  final String date;
  final String classSection;
  final String subject;
  final int periodNumber;
  final int? subjectId;
}

/// Saying what a period covered (docs/teacher-app.md, T3): the topic taught,
/// optionally the syllabus topic it ticks off, homework and remarks. The
/// same rules as the web, kept by the server: one report per period and
/// day, nothing dated ahead, and only the teacher's own periods.
class FileReportScreen extends ConsumerStatefulWidget {
  const FileReportScreen({super.key, required this.period});

  final ReportPeriod period;

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

  @override
  void dispose() {
    _topic.dispose();
    _homework.dispose();
    _remarks.dispose();
    super.dispose();
  }

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
    });

    try {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report filed.')));
      context.pop(true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _problem = _say(failure));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The server's refusals in a teacher's words; anything else as it came.
  String _say(Failure failure) => switch (failure.code) {
    'TEACHING_REPORT_ALREADY_SUBMITTED' =>
      'This period already has a report for ${formatIsoDate(widget.period.date)}. '
          'Pull down on Today to see it.',
    'NETWORK_ERROR' => 'No connection. Nothing was sent - try again when you have signal.',
    'FORBIDDEN' => 'This period is no longer yours on the timetable, so it cannot be reported from here.',
    _ => failure.message,
  };

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Teaching report'),
            Text(
              '${period.subject} · ${period.classSection} · Period ${period.periodNumber}',
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
                  if (_problem != null) ...[
                    Container(
                      key: const Key('report-problem'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text(_problem!, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    key: const Key('report-topic'),
                    controller: _topic,
                    enabled: !_sending,
                    maxLines: 3,
                    minLines: 2,
                    maxLength: topicLimit,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What was taught',
                      hintText: 'e.g. Fractions: adding unlike denominators',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Say what was taught in this period.' : null,
                  ),
                  const SizedBox(height: 8),
                  if (period.subjectId != null)
                    _SyllabusTopicChoice(
                      subjectId: period.subjectId!,
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
                    decoration: const InputDecoration(labelText: 'Homework (optional)'),
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
                    decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const Key('report-submit'),
                      onPressed: _sending ? null : _submit,
                      child: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('File report'),
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
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int subjectId;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return ref
        .watch(subjectTopicsProvider(subjectId))
        .when(
          loading: () => const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
          error: (_, _) => Padding(
            key: const Key('report-topics-unavailable'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'The syllabus could not be loaded, so no topic can be ticked off with this report. '
              'You can tick it later under Teaching.',
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ),
          data: (topics) {
            if (topics.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<int?>(
                key: const Key('report-syllabus-topic'),
                initialValue: value,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Syllabus topic (optional)',
                  helperText: 'Picking one ticks it off for this class',
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Not a syllabus topic')),
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
