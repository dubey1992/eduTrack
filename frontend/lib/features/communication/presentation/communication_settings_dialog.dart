import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/async_value_view.dart';
import '../application/message_page_notifier.dart';
import '../application/template_notifier.dart';
import '../data/models/message.dart';

/// The prototype's "Attendance & Communication" settings card: which alerts
/// a school sends, through which channels, and the provider accounts that
/// carry them.
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

/// The gateway that records messages without sending them.
const _demoGateway = 'log';

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
  late bool _whatsappEnabled = widget.settings.whatsappEnabled;
  late String _whatsappProvider = widget.settings.whatsappProvider;
  late bool _emailEnabled = widget.settings.emailEnabled;

  /// One controller per credential box, keyed "provider.key". Created on
  /// first use so a provider that is never shown never allocates one.
  final Map<String, TextEditingController> _credentialControllers = {};

  /// Credentials the administrator asked to wipe, keyed "provider.key".
  final Set<String> _cleared = {};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _senderIdController.dispose();
    for (final controller in _credentialControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The providers whose account boxes are shown: whichever gateways are
  /// chosen for SMS and WhatsApp, if they ask for anything at all.
  List<String> get _accountProviders => [
    for (final provider in {_provider, _whatsappProvider})
      if (widget.settings.credentialFields[provider]?.isNotEmpty ?? false) provider,
  ];

  TextEditingController _controllerFor(String provider, String key) =>
      _credentialControllers.putIfAbsent('$provider.$key', TextEditingController.new);

  /// Only what was typed or cleared. A box left blank is not sent, so the
  /// server keeps whatever it has - a saved secret never needs re-entering.
  Map<String, Map<String, String>>? _credentialsToSend() {
    final payload = <String, Map<String, String>>{};

    for (final provider in _accountProviders) {
      for (final field in widget.settings.credentialFields[provider]!) {
        final id = '$provider.${field.key}';
        final typed = _credentialControllers[id]?.text.trim() ?? '';

        if (_cleared.contains(id)) {
          payload.putIfAbsent(provider, () => {})[field.key] = '';
        } else if (typed.isNotEmpty) {
          payload.putIfAbsent(provider, () => {})[field.key] = typed;
        }
      }
    }

    return payload.isEmpty ? null : payload;
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
            whatsappEnabled: _whatsappEnabled,
            whatsappProvider: _whatsappProvider,
            emailEnabled: _emailEnabled,
            credentials: _credentialsToSend(),
          );

      // The server now holds what was typed; the boxes go back to "Saved".
      for (final controller in _credentialControllers.values) {
        controller.clear();
      }
      _cleared.clear();

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

  String _providerLabel(String value) {
    for (final option in [...widget.settings.availableProviders, ...widget.settings.availableWhatsappProviders]) {
      if (option.value == value) return option.label;
    }
    return value;
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
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'SMS Provider'),
            items: [
              for (final option in settings.availableProviders)
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
          const SizedBox(height: 16),
          const _SectionTitle('WhatsApp'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable WhatsApp'),
            subtitle: const Text('Send a WhatsApp copy of every alert and message that has a template mapped.'),
            value: _whatsappEnabled,
            onChanged: (value) => setState(() => _whatsappEnabled = value),
          ),
          if (settings.availableWhatsappProviders.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: settings.availableWhatsappProviders.any((o) => o.value == _whatsappProvider)
                  ? _whatsappProvider
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'WhatsApp Provider'),
              items: [
                for (final option in settings.availableWhatsappProviders)
                  DropdownMenuItem(value: option.value, child: Text(option.label)),
              ],
              onChanged: (value) => setState(() => _whatsappProvider = value ?? _whatsappProvider),
            ),
          ],
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
          const SizedBox(height: 16),
          const _SectionTitle('Provider accounts'),
          if (_accountProviders.isEmpty)
            Text('The chosen gateways need no account details.', style: muted)
          else
            for (final provider in _accountProviders) ...[
              const SizedBox(height: 4),
              Text(_providerLabel(provider), style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final field in settings.credentialFields[provider]!) ...[
                const SizedBox(height: 8),
                _CredentialBox(
                  field: field,
                  status: settings.statusOf(provider, field.key),
                  controller: _controllerFor(provider, field.key),
                  cleared: _cleared.contains('$provider.${field.key}'),
                  onClearToggled: (cleared) => setState(() {
                    final id = '$provider.${field.key}';
                    cleared ? _cleared.add(id) : _cleared.remove(id);
                  }),
                  // Typing something new is the opposite of clearing it.
                  onTyped: () {
                    if (_cleared.remove('$provider.${field.key}')) setState(() {});
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: settings.provider == _demoGateway ? null : () => _sendTest(MessageChannel.sms),
                icon: const Icon(Icons.sms_outlined, size: 18),
                label: const Text('Send test SMS'),
              ),
              OutlinedButton.icon(
                onPressed: settings.whatsappProvider == _demoGateway ? null : () => _sendTest(MessageChannel.whatsapp),
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

/// One credential. Never prefilled - the server does not hand values back -
/// so the helper says what is on file and the box only carries a change.
class _CredentialBox extends StatelessWidget {
  const _CredentialBox({
    required this.field,
    required this.status,
    required this.controller,
    required this.cleared,
    required this.onClearToggled,
    required this.onTyped,
  });

  final CredentialField field;
  final CredentialStatus status;
  final TextEditingController controller;
  final bool cleared;
  final ValueChanged<bool> onClearToggled;
  final VoidCallback onTyped;

  String? get _helper {
    if (cleared) return 'Will be cleared when you save.';
    if (!status.isSet) return null;
    if (field.secret) return 'Saved - leave blank to keep';
    return status.hint == null ? 'Saved - leave blank to keep' : 'On file: ${status.hint}';
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: field.secret,
      onChanged: (_) => onTyped(),
      decoration: InputDecoration(
        labelText: field.label,
        helperText: _helper,
        helperStyle: cleared ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
        suffixIcon: status.isSet
            ? IconButton(
                tooltip: cleared ? 'Keep ${field.label}' : 'Clear ${field.label}',
                icon: Icon(cleared ? Icons.undo : Icons.backspace_outlined, size: 18),
                onPressed: () => onClearToggled(!cleared),
              )
            : null,
      ),
    );
  }
}

/// Asks for a number, sends one message through the school's saved provider
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
