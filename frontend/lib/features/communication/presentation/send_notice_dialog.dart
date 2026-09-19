import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/date_format.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../staff/data/models/staff_profile.dart';
import '../../staff/data/staff_repository.dart';
import '../../students/data/models/student.dart';
import '../../students/data/student_repository.dart';
import '../application/message_page_notifier.dart';
import '../application/template_notifier.dart';
import '../data/models/message.dart';

/// How long the form waits after the last change before counting the
/// audience again, so typing a name does not fire a request per keystroke.
const _previewDebounce = Duration(milliseconds: 400);

/// The Communication Center's "Send Message": a message to one person or a
/// group, an emergency alert, or a fee reminder, written by hand.
class SendNoticeDialog extends ConsumerStatefulWidget {
  const SendNoticeDialog({super.key, required this.schoolId});

  final int? schoolId;

  @override
  ConsumerState<SendNoticeDialog> createState() => _SendNoticeDialogState();
}

class _SendNoticeDialogState extends ConsumerState<SendNoticeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _amountController = TextEditingController();

  NoticeKind _kind = NoticeKind.message;
  NoticeAudience _audience = NoticeAudience.student;
  int? _targetId;
  NoticeRecipients _recipients = NoticeRecipients.guardians;
  Set<MessageChannel> _channels = {MessageChannel.sms};
  bool _channelsTouched = false;
  DateTime? _dueDate;

  NoticeQuery? _committedQuery;
  Timer? _debounce;

  bool _sending = false;
  String? _error;
  String? _targetError;
  String? _channelsError;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    // The school decides which channels are on offer; until that answer
    // arrives the form assumes SMS, the one every school starts with.
    ref.read(communicationSettingsNotifierProvider(widget.schoolId).future).then((settings) {
      if (!mounted || _channelsTouched) return;
      setState(() {
        _channels = {settings.smsEnabled ? MessageChannel.sms : MessageChannel.inApp};
        _committedQuery = _buildQuery();
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subjectController.dispose();
    _bodyController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  bool get _targetReady => !_audience.needsTarget || _targetId != null;

  NoticeQuery? _buildQuery() {
    if (!_targetReady || _channels.isEmpty) return null;

    return NoticeQuery(
      kind: _kind,
      audienceType: _audience,
      audienceId: _audience.needsTarget ? _targetId : null,
      recipients: _audience.choosesRecipients ? _recipients : null,
      channels: _channels.toList(),
      schoolId: widget.schoolId,
    );
  }

  /// Every change to who or how goes through here, so the reach count
  /// follows the form after a short pause rather than on every tap.
  void _changed(VoidCallback update) {
    setState(() {
      update();
      _error = null;
      _fieldErrors = const {};
    });
    _debounce?.cancel();
    _debounce = Timer(_previewDebounce, () {
      if (mounted) setState(() => _committedQuery = _buildQuery());
    });
  }

  void _setKind(NoticeKind kind) {
    _changed(() {
      _kind = kind;
      // An emergency is for everyone; a fee reminder is about one student.
      if (kind == NoticeKind.emergency) _setAudienceQuietly(NoticeAudience.everyone);
      if (kind == NoticeKind.feeReminder) _setAudienceQuietly(NoticeAudience.student);
    });
  }

  void _setAudienceQuietly(NoticeAudience audience) {
    if (_audience == audience) return;
    _audience = audience;
    _targetId = null;
    _targetError = null;
  }

  String? _fieldError(String field) => _fieldErrors[field]?.firstOrNull;

  Future<void> _pickDueDate() async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? today.add(const Duration(days: 7)),
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'Fee due on',
    );

    if (picked != null) _changed(() => _dueDate = picked);
  }

  Future<bool> _confirmEmergency() async {
    final audience = _audience == NoticeAudience.everyone ? 'everyone in the school' : _audience.label.toLowerCase();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send emergency alert?'),
        content: Text('Send this emergency alert to $audience?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Send alert')),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _send() async {
    if (_sending) return;

    final valid = _formKey.currentState!.validate();
    setState(() {
      _targetError = _targetReady ? null : 'Pick who this message is for.';
      _channelsError = _channels.isEmpty ? 'Pick at least one channel.' : null;
      if (_kind == NoticeKind.feeReminder && _dueDate == null) {
        _fieldErrors = {
          ..._fieldErrors,
          'due_date': ['Pick the date the fee is due.'],
        };
      }
    });
    if (!valid || _targetError != null || _channelsError != null || _fieldError('due_date') != null) return;

    if (_kind == NoticeKind.emergency && !await _confirmEmergency()) return;
    if (!mounted) return;

    setState(() {
      _sending = true;
      _error = null;
      _fieldErrors = const {};
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final subject = _subjectController.text.trim();
    final body = _bodyController.text.trim();
    final isFee = _kind == NoticeKind.feeReminder;

    try {
      final result = await ref
          .read(messagePageNotifierProvider.notifier)
          .sendNotice(
            schoolId: widget.schoolId,
            kind: _kind,
            audienceType: _audience,
            audienceId: _audience.needsTarget ? _targetId : null,
            recipients: _audience.choosesRecipients ? _recipients : null,
            channels: _channels.toList(),
            subject: isFee || subject.isEmpty ? null : subject,
            body: isFee ? null : body,
            amount: isFee ? _amountController.text.trim() : null,
            dueDate: isFee && _dueDate != null ? apiDate(_dueDate!) : null,
          );

      navigator.pop();
      final people = '${result.recipients} ${result.recipients == 1 ? 'person' : 'people'}';
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(result.queued ? 'Queued for $people.' : 'Sent to $people.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() {
        _error = failure.message;
        _fieldErrors = failure.validationErrors;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final settings = ref.watch(communicationSettingsNotifierProvider(widget.schoolId));
    // Until the school's switches are known, or if they cannot be read, every
    // channel is offered; the server refuses one that is off, by name.
    final available = settings.value?.enabledChannels ?? MessageChannel.values;
    final isFee = _kind == NoticeKind.feeReminder;

    return AlertDialog(
      title: const Text('Send Message'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 560, maxWidth: 560, maxHeight: 640),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<NoticeKind>(
                  showSelectedIcon: false,
                  segments: [for (final kind in NoticeKind.values) ButtonSegment(value: kind, label: Text(kind.label))],
                  selected: {_kind},
                  onSelectionChanged: (selection) => _setKind(selection.first),
                ),
                if (_kind == NoticeKind.emergency) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: scheme.errorContainer,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'An emergency alert goes out at once on every channel you pick. '
                              'Use it only when people need to act now.',
                              style: TextStyle(color: scheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<NoticeAudience>(
                  key: ValueKey('audience-${_audience.apiValue}'),
                  initialValue: _audience,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: [
                    for (final audience in NoticeAudience.values)
                      DropdownMenuItem(value: audience, child: Text(audience.label)),
                  ],
                  onChanged: (value) => _changed(() => _setAudienceQuietly(value ?? _audience)),
                ),
                if (_audience == NoticeAudience.student) ...[
                  const SizedBox(height: 12),
                  _PersonSearch<Student>(
                    key: const ValueKey('student-search'),
                    fieldLabel: 'Student',
                    hint: 'Type a name or admission number',
                    search: (term) => ref.read(studentRepositoryProvider).list(schoolId: widget.schoolId, search: term),
                    describe: (student) => '${student.name} - ${student.admissionNumber}',
                    errorText: _targetError ?? _fieldError('audience_id'),
                    onSelected: (student) => _changed(() => _targetId = student?.id),
                  ),
                ],
                if (_audience == NoticeAudience.staffMember) ...[
                  const SizedBox(height: 12),
                  _PersonSearch<StaffProfile>(
                    key: const ValueKey('staff-search'),
                    fieldLabel: 'Staff member',
                    hint: 'Type a name',
                    search: (term) => ref.read(staffRepositoryProvider).list(schoolId: widget.schoolId, search: term),
                    describe: (profile) => '${profile.name} - ${profile.employeeId}',
                    errorText: _targetError ?? _fieldError('audience_id'),
                    // The server addresses staff by their login, not the profile.
                    onSelected: (profile) => _changed(() => _targetId = profile?.userId),
                  ),
                ],
                if (_audience == NoticeAudience.classSection) ...[
                  const SizedBox(height: 12),
                  _ClassSectionPicker(
                    schoolId: widget.schoolId,
                    selected: _targetId,
                    errorText: _targetError ?? _fieldError('audience_id'),
                    onChanged: (value) => _changed(() => _targetId = value),
                  ),
                ],
                if (_audience == NoticeAudience.department) ...[
                  const SizedBox(height: 12),
                  _DepartmentPicker(
                    schoolId: widget.schoolId,
                    selected: _targetId,
                    errorText: _targetError ?? _fieldError('audience_id'),
                    onChanged: (value) => _changed(() => _targetId = value),
                  ),
                ],
                if (_audience.choosesRecipients) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<NoticeRecipients>(
                    initialValue: _recipients,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Send to'),
                    items: [
                      for (final option in NoticeRecipients.values)
                        DropdownMenuItem(value: option, child: Text(option.label)),
                    ],
                    onChanged: (value) => _changed(() => _recipients = value ?? _recipients),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Channels', style: muted),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final channel in available)
                      FilterChip(
                        label: Text(channel.label),
                        selected: _channels.contains(channel),
                        onSelected: (selected) => _changed(() {
                          _channelsTouched = true;
                          _channelsError = null;
                          selected ? _channels.add(channel) : _channels.remove(channel);
                        }),
                      ),
                  ],
                ),
                if (_channelsError != null || _fieldError('channels') != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _channelsError ?? _fieldError('channels')!,
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                  ),
                if (settings.value?.whatsappEnabled ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('WhatsApp needs a template mapped for this kind of message.', style: muted),
                  ),
                const SizedBox(height: 12),
                if (!isFee) ...[
                  TextFormField(
                    controller: _subjectController,
                    decoration: InputDecoration(
                      labelText: _kind == NoticeKind.message ? 'Subject' : 'Subject (optional)',
                      errorText: _fieldError('subject'),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (_kind == NoticeKind.message && text.isEmpty) return 'Enter a subject.';
                      if (text.length > 150) return 'Keep the subject under 150 characters.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bodyController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                      errorText: _fieldError('body'),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return 'Enter the message to send.';
                      if (text.length < 10) return 'That message is too short.';
                      if (text.length > 1000) return 'Keep the message under 1000 characters.';
                      return null;
                    },
                  ),
                ] else ...[
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount due',
                      helperText: "In the school's currency",
                      errorText: _fieldError('amount'),
                    ),
                    validator: (value) {
                      final amount = double.tryParse((value ?? '').trim());
                      if (amount == null) return 'Enter the amount due.';
                      if (amount <= 0) return 'The amount must be more than zero.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dueDate == null ? 'No due date picked yet.' : 'Due on ${formatDate(_dueDate!)}.',
                          style: _fieldError('due_date') == null ? muted : TextStyle(fontSize: 12, color: scheme.error),
                        ),
                      ),
                      TextButton(onPressed: _pickDueDate, child: Text(_dueDate == null ? 'Pick date' : 'Change')),
                    ],
                  ),
                  if (_fieldError('due_date') != null)
                    Text(_fieldError('due_date')!, style: TextStyle(fontSize: 12, color: scheme.error)),
                ],
                const SizedBox(height: 12),
                if (_committedQuery == null)
                  Text(
                    _channels.isEmpty
                        ? 'Pick a channel to see how many people this reaches.'
                        : 'Pick who this is for to see how many people it reaches.',
                    style: muted,
                  )
                else
                  _ReachLine(query: _committedQuery!),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(_kind == NoticeKind.emergency ? 'Send alert' : 'Send'),
        ),
      ],
    );
  }
}

/// "Reaches 42 people · SMS 40 · In-app 12" - so nobody sends to a bigger
/// audience than they meant to.
class _ReachLine extends ConsumerWidget {
  const _ReachLine({required this.query});

  final NoticeQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(noticePreviewProvider(query));
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return preview.when(
      loading: () => Text('Counting who this reaches…', style: muted),
      error: (error, _) => Text(
        error is Failure ? error.message : 'The reach count is unavailable.',
        style: TextStyle(fontSize: 12, color: scheme.error),
      ),
      data: (result) {
        if (result.recipients == 0) {
          return Text(
            'Nobody in this audience can be reached on these channels.',
            style: TextStyle(fontSize: 12, color: scheme.error),
          );
        }

        final perChannel = [for (final channel in query.channels) '${channel.label} ${result.countFor(channel)}']
            .join(' · ');

        return Text(
          'Reaches ${result.recipients} ${result.recipients == 1 ? 'person' : 'people'} · $perChannel',
          style: muted,
        );
      },
    );
  }
}

/// A type-ahead over the school's students or staff. The search is the
/// server's, so the list only ever holds people the sender may reach.
class _PersonSearch<T extends Object> extends StatefulWidget {
  const _PersonSearch({
    super.key,
    required this.fieldLabel,
    required this.hint,
    required this.search,
    required this.describe,
    required this.onSelected,
    this.errorText,
  });

  final String fieldLabel;
  final String hint;
  final Future<List<T>> Function(String term) search;
  final String Function(T person) describe;
  final ValueChanged<T?> onSelected;
  final String? errorText;

  @override
  State<_PersonSearch<T>> createState() => _PersonSearchState<T>();
}

class _PersonSearchState<T extends Object> extends State<_PersonSearch<T>> {
  String? _searchError;
  String? _chosen;

  Future<Iterable<T>> _options(TextEditingValue value) async {
    final term = value.text.trim();
    if (term.isEmpty || term == _chosen) return const [];

    try {
      final found = await widget.search(term);
      if (mounted && _searchError != null) setState(() => _searchError = null);
      return found;
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _searchError = failure.message);
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<T>(
      displayStringForOption: widget.describe,
      optionsBuilder: _options,
      onSelected: (person) {
        _chosen = widget.describe(person);
        widget.onSelected(person);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.fieldLabel,
            hintText: widget.hint,
            helperText: _searchError,
            helperStyle: TextStyle(color: Theme.of(context).colorScheme.error),
            errorText: widget.errorText,
            suffixIcon: const Icon(Icons.search),
          ),
          onChanged: (text) {
            // Editing the name after picking someone un-picks them.
            if (_chosen != null && text != _chosen) {
              _chosen = null;
              widget.onSelected(null);
            }
          },
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 480),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(dense: true, title: Text(widget.describe(option)), onTap: () => onSelected(option)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClassSectionPicker extends ConsumerWidget {
  const _ClassSectionPicker({required this.schoolId, required this.selected, required this.onChanged, this.errorText});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(classSectionPickerProvider(schoolId));
    final options = state.value ?? const <ClassSectionOption>[];

    return DropdownButtonFormField<int>(
      key: ValueKey('notice-class-${options.length}'),
      initialValue: options.any((o) => o.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Class',
        errorText: errorText,
        helperText: state.isLoading
            ? 'Loading classes…'
            : (state.hasValue && options.isEmpty ? 'No classes have been set up yet.' : null),
      ),
      items: [for (final option in options) DropdownMenuItem(value: option.id, child: Text(option.label))],
      onChanged: state.isLoading ? null : onChanged,
    );
  }
}

class _DepartmentPicker extends ConsumerWidget {
  const _DepartmentPicker({required this.schoolId, required this.selected, required this.onChanged, this.errorText});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(departmentPickerProvider(schoolId));
    final departments = state.value ?? [];

    return DropdownButtonFormField<int>(
      key: ValueKey('notice-department-${departments.length}'),
      initialValue: departments.any((d) => d.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Department',
        errorText: errorText,
        helperText: state.isLoading
            ? 'Loading departments…'
            : (state.hasValue && departments.isEmpty ? 'No departments have been set up yet.' : null),
      ),
      items: [
        for (final department in departments) DropdownMenuItem(value: department.id, child: Text(department.name)),
      ],
      onChanged: state.isLoading ? null : onChanged,
    );
  }
}
