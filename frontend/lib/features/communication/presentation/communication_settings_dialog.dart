import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/async_value_view.dart';
import '../application/message_page_notifier.dart';
import '../application/template_notifier.dart';
import '../data/models/message.dart';

/// The prototype's "Attendance & Communication" settings card: which alerts
/// a school sends, and through which gateway.
class CommunicationSettingsDialog extends ConsumerWidget {
  const CommunicationSettingsDialog({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(communicationSettingsNotifierProvider(schoolId));

    return AlertDialog(
      title: const Text('Alert Settings'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 460, maxHeight: 520),
        child: SingleChildScrollView(
          child: AsyncValueView<CommunicationSettings>(
            value: settingsState,
            onRetry: () => ref.invalidate(communicationSettingsNotifierProvider(schoolId)),
            data: (context, settings) => _SettingsForm(settings: settings, schoolId: schoolId),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, required this.schoolId});

  final CommunicationSettings settings;
  final int? schoolId;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _smsEnabled = widget.settings.smsEnabled;
  late AttendanceAlertMode _attendanceAlerts = widget.settings.attendanceAlerts;
  late bool _transportAlerts = widget.settings.transportAlertsEnabled;
  late bool _leaveAlerts = widget.settings.leaveAlertsEnabled;
  late String _provider = widget.settings.provider;
  late final TextEditingController _senderIdController = TextEditingController(text: widget.settings.senderId ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _senderIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final senderId = _senderIdController.text.trim();

    try {
      await ref
          .read(communicationSettingsNotifierProvider(widget.schoolId).notifier)
          .save(
            smsEnabled: _smsEnabled,
            attendanceAlerts: _attendanceAlerts,
            transportAlertsEnabled: _transportAlerts,
            leaveAlertsEnabled: _leaveAlerts,
            provider: _provider,
            senderId: senderId.isEmpty ? null : senderId,
          );

      ref.invalidate(messageSummaryProvider);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Alert settings saved.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.settings.isSaved)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('This school is still on the default settings.', style: muted),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable parent SMS'),
            subtitle: const Text('Turn this off to stop every outgoing text for this school.'),
            value: _smsEnabled,
            onChanged: (value) => setState(() => _smsEnabled = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AttendanceAlertMode>(
            initialValue: _attendanceAlerts,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Send attendance alerts for'),
            items: [
              for (final mode in AttendanceAlertMode.values) DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: (value) => setState(() => _attendanceAlerts = value ?? _attendanceAlerts),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Transport alerts'),
            subtitle: const Text('Tell guardians when their child boards, is dropped off, or does not board.'),
            value: _transportAlerts,
            onChanged: (value) => setState(() => _transportAlerts = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Leave decision alerts'),
            subtitle: const Text('Tell staff when their leave is approved or rejected.'),
            value: _leaveAlerts,
            onChanged: (value) => setState(() => _leaveAlerts = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'SMS Provider'),
            items: [
              for (final option in widget.settings.availableProviders)
                DropdownMenuItem(value: option.value, child: Text(option.label)),
            ],
            onChanged: (value) => setState(() => _provider = value ?? _provider),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _senderIdController,
            decoration: const InputDecoration(
              labelText: 'Sender ID (optional)',
              helperText: 'Letters, numbers and hyphens only, e.g. SUNRIS',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null;
              if (text.length > 20) return 'A sender ID can be at most 20 characters.';
              if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(text)) {
                return 'A sender ID can only contain letters, numbers and hyphens.';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('Save Settings')),
        ],
      ),
    );
  }
}
