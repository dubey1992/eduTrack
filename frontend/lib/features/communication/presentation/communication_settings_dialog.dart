import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/async_value_view.dart';
import '../application/message_page_notifier.dart';
import '../application/template_notifier.dart';
import '../data/models/message.dart';

/// The prototype's "Attendance & Communication" settings card: which alerts
/// a school sends, and on which channels.
///
/// Who carries them is not the school's to choose: since 2026-10-29 every
/// school's SMS and WhatsApp go through School365ai's own account
/// (docs/platform-messaging.md). The card says so, and whether that account
/// is really sending yet.
class CommunicationSettingsDialog extends ConsumerWidget {
  const CommunicationSettingsDialog({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(communicationSettingsNotifierProvider(schoolId));

    return AlertDialog(
      title: const Text('Alert Settings'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 560, maxWidth: 560, maxHeight: 600),
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
  late bool _resultAlerts = widget.settings.resultAlertsEnabled;
  late bool _whatsappEnabled = widget.settings.whatsappEnabled;
  late bool _emailEnabled = widget.settings.emailEnabled;

  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(communicationSettingsNotifierProvider(widget.schoolId).notifier)
          .save(
            smsEnabled: _smsEnabled,
            attendanceAlerts: _attendanceAlerts,
            transportAlertsEnabled: _transportAlerts,
            leaveAlertsEnabled: _leaveAlerts,
            resultAlertsEnabled: _resultAlerts,
            whatsappEnabled: _whatsappEnabled,
            emailEnabled: _emailEnabled,
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

  Future<void> _sendTest(MessageChannel channel) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmation = await showDialog<String>(
      context: context,
      builder: (_) => _TestMessageDialog(schoolId: widget.schoolId, channel: channel),
    );

    if (confirmation == null) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(confirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final settings = widget.settings;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!settings.isSaved)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('This school is still on the default settings.', style: muted),
            ),
          _SentThrough(settings: settings),
          const SizedBox(height: 12),
          const _SectionTitle('SMS'),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Result alerts'),
            subtitle: const Text('Tell guardians the marks when a class test result is published.'),
            value: _resultAlerts,
            onChanged: (value) => setState(() => _resultAlerts = value),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('WhatsApp'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable WhatsApp'),
            subtitle: const Text('Send a WhatsApp copy of every alert and message that has a template mapped.'),
            value: _whatsappEnabled,
            onChanged: (value) => setState(() => _whatsappEnabled = value),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Email'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable email'),
            subtitle: const Text('Send an email copy to guardians and staff who have an address on record.'),
            value: _emailEnabled,
            onChanged: (value) => setState(() => _emailEnabled = value),
          ),
          if (!settings.emailDelivers)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No SMTP server is set up yet. The Super Admin can add one under Email Settings.',
                style: muted,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: settings.providerDelivers ? () => _sendTest(MessageChannel.sms) : null,
                icon: const Icon(Icons.sms_outlined, size: 18),
                label: const Text('Send test SMS'),
              ),
              OutlinedButton.icon(
                onPressed: settings.whatsappProviderDelivers ? () => _sendTest(MessageChannel.whatsapp) : null,
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('Send test WhatsApp'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Tests go through the saved settings - save first if you changed anything here.', style: muted),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// How this school's SMS and WhatsApp go out: School365ai's account, and
/// whether it is really sending yet.
class _SentThrough extends StatelessWidget {
  const _SentThrough({required this.settings});

  final CommunicationSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sending = settings.providerDelivers;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sending ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(sending ? Icons.verified_outlined : Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sending
                  ? 'SMS and WhatsApp are sent through School365ai. Switch on the channels and alerts you want below.'
                  : 'School365ai is still setting up SMS and WhatsApp. Until then messages are recorded in the '
                        'log but not sent to phones.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a number, sends one message through School365ai's account
/// and pops with the server's confirmation. A refusal is shown right here.
class _TestMessageDialog extends ConsumerStatefulWidget {
  const _TestMessageDialog({required this.schoolId, required this.channel});

  final int? schoolId;
  final MessageChannel channel;

  @override
  ConsumerState<_TestMessageDialog> createState() => _TestMessageDialogState();
}

class _TestMessageDialogState extends ConsumerState<_TestMessageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _toController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate() || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    final navigator = Navigator.of(context);

    try {
      final confirmation = await ref
          .read(communicationSettingsNotifierProvider(widget.schoolId).notifier)
          .sendTest(channel: widget.channel, to: _toController.text.trim());
      navigator.pop(confirmation);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send test ${widget.channel.label}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 360, maxWidth: 360),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _toController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  helperText: 'With the country code, e.g. +91 98765 43210',
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) return 'Enter the number to send the test to.';
                  if (digits.length < 7) return 'That does not look like a mobile number.';
                  return null;
                },
                onFieldSubmitted: (_) => _send(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _sending ? null : _send, child: const Text('Send')),
      ],
    );
  }
}
