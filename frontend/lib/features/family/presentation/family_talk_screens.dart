import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
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
    final l10n = context.l10n;

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
        SnackBar(content: Text(_toOffice ? l10n.familyCallSentOffice : l10n.familyCallSentTeacher)),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = {for (final entry in failure.validationErrors.entries) entry.key: entry.value.first};
        _problem = _fieldErrors.isEmpty || failure.code == 'CALL_REQUEST_OPEN'
            ? failure.localizedMessage(context)
            : null;
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
      appBar: AppBar(title: Text(context.l10n.familyAskToCall)),
      body: child == null
          ? FamilyEmptyView(icon: Icons.family_restroom_rounded, title: context.l10n.familyNoChildrenTitle)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    context.l10n.familyWhoShouldCall(child.firstName),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    key: const Key('family-call-recipient'),
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(context.l10n.familyClassTeacher),
                        icon: const Icon(Icons.school_outlined),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(context.l10n.familySchoolOfficeShort),
                        icon: const Icon(Icons.business_outlined),
                      ),
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
                    decoration: InputDecoration(
                      labelText: context.l10n.familyWhatAbout,
                      errorText: _fieldErrors['reason'],
                    ),
                    validator: (value) =>
                        (value ?? '').trim().length < callReasonMin ? context.l10n.familyWhatAboutTooShort : null,
                  ),
                  TextFormField(
                    key: const Key('family-call-time'),
                    controller: _time,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: context.l10n.familyGoodTimeToCall,
                      hintText: context.l10n.familyGoodTimeHint,
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
                        : Text(context.l10n.familyAskForCall),
                  ),
                  const SizedBox(height: 24),
                  Text(context.l10n.familyYourRequests, style: Theme.of(context).textTheme.titleMedium),
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
              ? Text(context.l10n.familyNoneYet, style: TextStyle(color: colours.muted))
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
    final l10n = context.l10n;

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
                  '${request.toOffice ? l10n.familySchoolOfficeShort : l10n.familyClassTeacher} · ${formatDate(request.sentAt)}'
                  '${request.preferredTime == null ? '' : ' · ${request.preferredTime}'}',
                  style: TextStyle(fontSize: 13, color: colours.muted),
                ),
                if (request.called && request.calledAt != null)
                  Text(
                    l10n.familyCalledBy(request.calledBy ?? l10n.familyTheSchool, formatDateTime(request.calledAt!)),
                    key: Key('family-call-done-${request.id}'),
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
              request.called ? l10n.familyCalled : l10n.familyWaiting,
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
      if (mounted) setState(() => _error = failure.localizedMessage(context));
    } finally {
      if (mounted) setState(() => _sendingFor = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final l10n = context.l10n;
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
                  ? l10n.familyAnswerBy(formatDate(reply.replyBy!))
                  : l10n.familyAnswersClosedOn(formatDate(reply.replyBy!)),
              style: TextStyle(fontSize: 12, color: colours.muted),
            ),
          const SizedBox(height: 10),
          for (final child in reply.children) ...[
            Padding(
              padding: EdgeInsets.only(bottom: child.answeredAt == null ? 8 : 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      child.answer == null
                          ? child.name
                          : '${child.name}: ${child.answer! ? l10n.familyYes : l10n.familyNo}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (reply.open) ...[
                    _AnswerButton(
                      key: Key('family-reply-yes-${child.studentId}'),
                      label: l10n.familyYes,
                      chosen: child.answer == true,
                      busy: _sendingFor == child.studentId,
                      onPressed: () => _answer(child.studentId, true),
                    ),
                    const SizedBox(width: 6),
                    _AnswerButton(
                      key: Key('family-reply-no-${child.studentId}'),
                      label: l10n.familyNo,
                      chosen: child.answer == false,
                      busy: _sendingFor == child.studentId,
                      onPressed: () => _answer(child.studentId, false),
                    ),
                  ],
                ],
              ),
            ),
            if (child.answeredAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.familyAnswerReached(formatDateTime(child.answeredAt!)),
                  key: Key('family-reply-received-${child.studentId}'),
                  style: TextStyle(fontSize: 12, color: colours.muted),
                ),
              ),
          ],
          if (reply.open)
            TextField(
              key: const Key('family-reply-note'),
              controller: _note,
              maxLength: 300,
              decoration: InputDecoration(labelText: l10n.familyNoteForSchool, isDense: true),
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
        context.l10n.familyAnswerNeeded,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colours.onWarningContainer),
      ),
    );
  }
}
