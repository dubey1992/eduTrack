import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_learning_notifiers.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_call_request.dart';
import '../data/models/family_records.dart';
import 'widgets/family_widgets.dart';

const callReasonMin = 5;
const callReasonMax = 300;

/// "Please call me" (docs/parent-student-app.md, F5): the parent picks the
/// class teacher or the school office, says what it is about and when suits
/// them, and sees each request marked called. Not a chat (decision D5).
class FamilyCallRequestScreen extends ConsumerStatefulWidget {
  const FamilyCallRequestScreen({super.key});

  @override
  ConsumerState<FamilyCallRequestScreen> createState() => _FamilyCallRequestScreenState();
}

class _FamilyCallRequestScreenState extends ConsumerState<FamilyCallRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _time = TextEditingController();
  bool _toOffice = false;
  bool _sending = false;
  Map<String, String> _fieldErrors = {};
  String? _problem;

  @override
  void dispose() {
    _reason.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    final child = ref.read(selectedChildProvider);
    if (child == null) return;

    setState(() {
      _sending = true;
      _fieldErrors = {};
      _problem = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final time = _time.text.trim();
      await ref
          .read(familyRepositoryProvider)
          .askForCall(
            child.id,
            toOffice: _toOffice,
            reason: _reason.text.trim(),
            preferredTime: time.isEmpty ? null : time,
          );
      ref.invalidate(familyCallRequestsProvider(child.id));
      _reason.clear();
      _time.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _toOffice ? 'Sent. The school office will call you.' : 'Sent. The class teacher will call you.',
          ),
        ),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = {for (final entry in failure.validationErrors.entries) entry.key: entry.value.first};
        _problem = _fieldErrors.isEmpty || failure.code == 'CALL_REQUEST_OPEN' ? failure.message : null;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final colours = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Ask the school to call you')),
      body: child == null
          ? const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show')
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text('Who should call you about ${child.firstName}?', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    key: const Key('family-call-recipient'),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Class teacher'), icon: Icon(Icons.school_outlined)),
                      ButtonSegment(value: true, label: Text('School office'), icon: Icon(Icons.business_outlined)),
                    ],
                    selected: {_toOffice},
                    onSelectionChanged: (choice) => setState(() => _toOffice = choice.first),
                  ),
                  if (_fieldErrors['recipient'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_fieldErrors['recipient']!, style: TextStyle(color: colours.danger, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('family-call-reason'),
                    controller: _reason,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: callReasonMax,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: 'What is it about?', errorText: _fieldErrors['reason']),
                    validator: (value) =>
                        (value ?? '').trim().length < callReasonMin ? 'Please say a little about what it is.' : null,
                  ),
                  TextFormField(
                    key: const Key('family-call-time'),
                    controller: _time,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'A good time to call (optional)',
                      hintText: 'e.g. After 5 pm',
                      errorText: _fieldErrors['preferred_time'],
                    ),
                  ),
                  if (_problem != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('family-call-problem'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colours.warningContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_problem!, style: TextStyle(color: colours.onWarningContainer)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('family-call-send'),
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ask for a call'),
                  ),
                  const SizedBox(height: 24),
                  Text('Your requests', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _RequestList(childId: child.id),
                ],
              ),
            ),
    );
  }
}

class _RequestList extends ConsumerWidget {
  const _RequestList({required this.childId});

  final int childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = context.appColors;

    return ref
        .watch(familyCallRequestsProvider(childId))
        .when(
          // A bar, not PlaceholderCards: those are a list of their own, and a list
          // inside this page's list has no height to take.
          loading: () => const LinearProgressIndicator(),
          error: (error, _) =>
              FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyCallRequestsProvider(childId))),
          data: (requests) => requests.isEmpty
              ? Text('None yet.', style: TextStyle(color: colours.muted))
              : Column(
                  children: [
                    for (final request in requests) ...[_RequestCard(request: request), const SizedBox(height: 8)],
                  ],
                ),
        );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final FamilyCallRequest request;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return FamilyCard(
      key: Key('family-call-${request.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.reason, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${request.toOffice ? 'School office' : 'Class teacher'} · ${formatDate(request.sentAt)}'
                  '${request.preferredTime == null ? '' : ' · ${request.preferredTime}'}',
                  style: TextStyle(fontSize: 13, color: colours.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: request.called ? colours.successContainer : colours.infoContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              request.called ? 'Called' : 'Waiting',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: request.called ? colours.onSuccessContainer : colours.onInfoContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Under a notice that asks (F5): the question, and Yes or No for each of the
/// parent's children it is about, with a note if they want. They may change
/// an answer until the school's last day.
class NoticeReplyPanel extends ConsumerStatefulWidget {
  const NoticeReplyPanel({super.key, required this.notice});

  final FamilyNotice notice;

  @override
  ConsumerState<NoticeReplyPanel> createState() => _NoticeReplyPanelState();
}

class _NoticeReplyPanelState extends ConsumerState<NoticeReplyPanel> {
  late NoticeReply _reply = widget.notice.reply!;
  final _note = TextEditingController();
  int? _sendingFor;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _answer(int studentId, bool answer) async {
    if (_sendingFor != null) return;
    setState(() {
      _sendingFor = studentId;
      _error = null;
    });

    try {
      final note = _note.text.trim();
      final updated = await ref
          .read(familyNoticesProvider.notifier)
          .reply(widget.notice, studentId: studentId, answer: answer, note: note.isEmpty ? null : note);
      if (mounted) setState(() => _reply = updated);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sendingFor = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final reply = _reply;

    return Container(
      key: const Key('family-notice-reply'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reply.question, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (reply.replyBy != null)
            Text(
              reply.open
                  ? 'Please answer by ${formatDate(reply.replyBy!)}'
                  : 'Answers closed on ${formatDate(reply.replyBy!)}',
              style: TextStyle(fontSize: 12, color: colours.muted),
            ),
          const SizedBox(height: 10),
          for (final child in reply.children)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      child.answer == null ? child.name : '${child.name}: ${child.answer! ? 'Yes' : 'No'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (reply.open) ...[
                    _AnswerButton(
                      key: Key('family-reply-yes-${child.studentId}'),
                      label: 'Yes',
                      chosen: child.answer == true,
                      busy: _sendingFor == child.studentId,
                      onPressed: () => _answer(child.studentId, true),
                    ),
                    const SizedBox(width: 6),
                    _AnswerButton(
                      key: Key('family-reply-no-${child.studentId}'),
                      label: 'No',
                      chosen: child.answer == false,
                      busy: _sendingFor == child.studentId,
                      onPressed: () => _answer(child.studentId, false),
                    ),
                  ],
                ],
              ),
            ),
          if (reply.open)
            TextField(
              key: const Key('family-reply-note'),
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'A note for the school (optional)', isDense: true),
            ),
          if (_error != null) Text(_error!, style: TextStyle(color: colours.danger, fontSize: 13)),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    super.key,
    required this.label,
    required this.chosen,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool chosen;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return chosen
        ? FilledButton(onPressed: busy ? null : onPressed, child: Text(label))
        : OutlinedButton(onPressed: busy ? null : onPressed, child: Text(label));
  }
}

/// "Answer needed" on a notice still waiting for one of the parent's answers.
class AnswerNeededBadge extends StatelessWidget {
  const AnswerNeededBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: colours.warningContainer, borderRadius: BorderRadius.circular(99)),
      child: Text(
        'Answer needed',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colours.onWarningContainer),
      ),
    );
  }
}
