import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../../departments/application/department_picker_provider.dart';
import '../application/announcement_page_notifier.dart';
import '../data/models/announcement.dart';
import '../../../core/utils/date_format.dart';

/// The prototype's "New Announcement" modal: audience, channel, title and
/// message, plus an optional expiry and a live count of who it reaches.
class NewAnnouncementDialog extends ConsumerStatefulWidget {
  const NewAnnouncementDialog({super.key, required this.schoolId});

  final int? schoolId;

  @override
  ConsumerState<NewAnnouncementDialog> createState() => _NewAnnouncementDialogState();
}

class _NewAnnouncementDialogState extends ConsumerState<NewAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  AnnouncementAudience _audience = AnnouncementAudience.allSchool;
  bool _audienceSetForRole = false;
  AnnouncementChannels _channels = AnnouncementChannels.smsAndInApp;
  int? _target;
  DateTime? _expiresAt;
  bool _publishing = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _ready => !_audience.needsTarget || _target != null;

  /// A head of department may only reach the department they head, so the
  /// form offers them that and nothing else rather than inviting a refusal.
  bool get _departmentOnly => ref.watch(authNotifierProvider).value?.role == UserRole.hod;

  List<AnnouncementAudience> get _audienceChoices =>
      _departmentOnly ? const [AnnouncementAudience.department] : AnnouncementAudience.values;

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate() || _publishing) return;

    if (_audience.needsTarget && _target == null) {
      setState(() => _error = 'Pick the class or department this announcement is for.');
      return;
    }

    setState(() {
      _publishing = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final published = await ref
          .read(announcementPageNotifierProvider.notifier)
          .publish(
            schoolId: widget.schoolId,
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            audienceType: _audience,
            audienceId: _audience.needsTarget ? _target : null,
            channels: _channels,
            expiresAt: _expiresAt == null ? null : DateFormat('yyyy-MM-dd').format(_expiresAt!),
          );

      navigator.pop();
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Announcement published to ${published.recipientsCount} '
              '${published.recipientsCount == 1 ? 'person' : 'people'}.',
            ),
          ),
        );
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _pickExpiry() async {
    // The school's today: the API rejects an expiry before it, so offering
    // an earlier one here would only produce a 422.
    final now = ref.read(schoolClockProvider).today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Drop from the feed after',
    );

    if (picked != null) setState(() => _expiresAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    if (!_audienceSetForRole && _departmentOnly) {
      _audience = AnnouncementAudience.department;
      _audienceSetForRole = true;
    }

    return AlertDialog(
      title: const Text('New Announcement'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 520, maxHeight: 560),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<AnnouncementAudience>(
                  initialValue: _audience,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: [
                    for (final audience in _audienceChoices)
                      DropdownMenuItem(value: audience, child: Text(audience.label)),
                  ],
                  onChanged: (value) => setState(() {
                    _audience = value ?? _audience;
                    _target = null;
                    // A stale rejection from the previous choice would be
                    // misleading next to a fresh audience.
                    _error = null;
                  }),
                ),
                if (_audience == AnnouncementAudience.classSection) ...[
                  const SizedBox(height: 12),
                  _ClassPicker(
                    schoolId: widget.schoolId,
                    selected: _target,
                    onChanged: (value) => setState(() => _target = value),
                  ),
                ],
                if (_audience == AnnouncementAudience.department) ...[
                  const SizedBox(height: 12),
                  _DepartmentPicker(
                    schoolId: widget.schoolId,
                    selected: _target,
                    onlyHeadedBy: _departmentOnly ? ref.watch(authNotifierProvider).value?.id : null,
                    onChanged: (value) => setState(() {
                      _target = value;
                      _error = null;
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<AnnouncementChannels>(
                  initialValue: _channels,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Send by'),
                  items: [
                    for (final channels in AnnouncementChannels.values)
                      DropdownMenuItem(value: channels, child: Text(channels.label)),
                  ],
                  onChanged: (value) => setState(() {
                    _channels = value ?? _channels;
                    _error = null;
                  }),
                ),
                if (_channels == AnnouncementChannels.inAppOnly && !_audience.reachesStaff)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Guardians have no app login, so this audience can only be reached by SMS.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Announcement title'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Enter a title.';
                    if (text.length < 3) return 'That title is too short.';
                    if (text.length > 150) return 'Keep the title under 150 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Enter the message to send.';
                    if (text.length < 10) return 'That message is too short.';
                    if (text.length > 2000) return 'Keep the message under 2000 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiresAt == null
                            ? 'Stays in the feed until it is deleted.'
                            : 'Drops from the feed after ${formatDate(_expiresAt!)}.',
                        style: muted,
                      ),
                    ),
                    TextButton(onPressed: _pickExpiry, child: Text(_expiresAt == null ? 'Set expiry' : 'Change')),
                    if (_expiresAt != null)
                      IconButton(
                        tooltip: 'Clear expiry',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _expiresAt = null),
                      ),
                  ],
                ),
                if (_ready) ...[
                  const SizedBox(height: 4),
                  _AudienceSummary(
                    query: AudienceQuery(
                      audienceType: _audience,
                      channels: _channels,
                      schoolId: widget.schoolId,
                      audienceId: _audience.needsTarget ? _target : null,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _publishing ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _publishing ? null : _publish, child: const Text('Publish')),
      ],
    );
  }
}

/// "Goes to 312 people (310 by SMS, 24 in-app)" - so nobody publishes to a
/// bigger audience than they meant to.
class _AudienceSummary extends ConsumerWidget {
  const _AudienceSummary({required this.query});

  final AudienceQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(audiencePreviewProvider(query));
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return preview.when(
      loading: () => Text('Counting the audience…', style: muted),
      error: (error, _) => Text('The audience count is unavailable.', style: muted),
      data: (data) => Text(
        data.recipients == 0
            ? 'Nobody in this audience can be reached on that channel.'
            : 'Goes to ${data.recipients} ${data.recipients == 1 ? 'person' : 'people'} '
                  '(${data.sms} by SMS, ${data.inApp} in-app).',
        style: data.recipients == 0 ? TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error) : muted,
      ),
    );
  }
}

class _ClassPicker extends ConsumerWidget {
  const _ClassPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(classSectionPickerProvider(schoolId));
    final options = state.value ?? const <ClassSectionOption>[];

    return DropdownButtonFormField<int>(
      key: ValueKey('announcement-class-${options.length}'),
      initialValue: options.any((o) => o.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Class',
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
  const _DepartmentPicker({required this.schoolId, required this.selected, required this.onChanged, this.onlyHeadedBy});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  /// When set, only departments this user heads are offered.
  final int? onlyHeadedBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(departmentPickerProvider(schoolId));
    final all = state.value ?? [];
    final departments = onlyHeadedBy == null
        ? all
        : all.where((department) => department.hodUserId == onlyHeadedBy).toList();

    return DropdownButtonFormField<int>(
      key: ValueKey('announcement-department-${departments.length}'),
      initialValue: departments.any((d) => d.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Department',
        helperText: state.isLoading
            ? 'Loading departments…'
            : (state.hasValue && departments.isEmpty
                  ? (onlyHeadedBy == null
                        ? 'No departments have been set up yet.'
                        : 'You do not head a department yet.')
                  : null),
      ),
      items: [
        for (final department in departments) DropdownMenuItem(value: department.id, child: Text(department.name)),
      ],
      onChanged: state.isLoading ? null : onChanged,
    );
  }
}
