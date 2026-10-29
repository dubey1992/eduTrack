import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../../core/widgets/section_header.dart';
import '../application/platform_messaging_notifier.dart';
import '../data/models/platform_messaging.dart';
import 'widgets/whatsapp_templates_card.dart';

/// The provider whose settings the form asks for. The Demo Gateway has none.
const _twilio = 'twilio';

/// The settings that are sender numbers, checked for the international form
/// before they are sent.
const _senderNumberKeys = {'sms_from', 'whatsapp_from'};

/// School365ai's own SMS and WhatsApp account, which sends every school's
/// messages (docs/platform-messaging.md). Super Admin only - the API refuses
/// everyone else, and the nav item is not shown to them.
class PlatformMessagingScreen extends ConsumerWidget {
  const PlatformMessagingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(platformMessagingNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Messaging'),
        Expanded(
          child: AsyncValueView<PlatformMessaging>(
            value: settingsState,
            onRetry: () => ref.read(platformMessagingNotifierProvider.notifier).load(),
            data: (context, settings) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PlatformNote(),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _AccountForm(settings: settings),
                        ),
                      ),
                      const SizedBox(height: 16),
                      WhatsappTemplatesCard(events: settings.whatsappTemplates),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Whose account this is, so nobody looks for a school's own keys here.
class _PlatformNote extends StatelessWidget {
  const _PlatformNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.infoContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: colors.onInfoContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "This account sends every school's SMS and WhatsApp. Schools only switch each channel on or off.",
              style: TextStyle(color: colors.onInfoContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({required this.settings});

  final PlatformMessaging settings;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  final _formKey = GlobalKey<FormState>();

  /// One empty box per setting. Nothing stored is ever put back in them:
  /// an empty box means "keep what is saved".
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.settings.fields) field.key: TextEditingController(),
  };

  late String _provider = widget.settings.provider;

  /// Settings the Super Admin asked to remove; the save sends them empty.
  final Set<String> _clearing = {};

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  /// Only what the Super Admin touched: a typed value replaces the stored
  /// one, a removed setting goes out empty, and everything else is left out
  /// so the server keeps it. A secret is never sent back to keep it.
  Map<String, String> get _credentialsToSend {
    if (_provider != _twilio) return const {};

    final changes = <String, String>{};
    for (final field in widget.settings.fields) {
      final typed = _controllers[field.key]!.text.trim();
      if (_clearing.contains(field.key)) {
        changes[field.key] = '';
      } else if (typed.isNotEmpty) {
        changes[field.key] = typed;
      }
    }
    return changes;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(platformMessagingNotifierProvider.notifier)
          .save(provider: _provider, credentials: _credentialsToSend);

      if (!mounted) return;
      // What was typed is now what is stored; the boxes go back to meaning
      // "keep it".
      for (final controller in _controllers.values) {
        controller.clear();
      }
      setState(_clearing.clear);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Messaging settings saved.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _error = failure.message;
          _fieldErrors = failure.validationErrors;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openTestDialog(MessagingChannel channel) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _TestMessageDialog(channel: channel),
    );
    if (message == null || !mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  MessagingProviderOption? get _selectedOption {
    for (final option in widget.settings.availableProviders) {
      if (option.value == _provider) return option;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final colors = context.appColors;
    final muted = TextStyle(fontSize: 13, color: colors.muted);
    final delivers = _selectedOption?.delivers ?? false;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusLine(settings: settings),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('messaging-provider'),
            initialValue: _selectedOption?.value,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Send through', errorText: _serverError('provider')),
            items: [
              for (final option in settings.availableProviders)
                DropdownMenuItem(value: option.value, child: Text(option.label)),
            ],
            onChanged: _saving ? null : (value) => setState(() => _provider = value ?? _provider),
          ),
          const SizedBox(height: 6),
          Text(
            delivers
                ? "Every school's SMS and WhatsApp go out through this account."
                : 'The Demo Gateway records every message and sends nothing - no SMS or WhatsApp reaches anyone.',
            style: TextStyle(fontSize: 13, color: delivers ? colors.muted : colors.warning),
          ),
          if (_provider == _twilio) ...[
            const SizedBox(height: 16),
            Text(
              'Enter sender numbers in full international form, like +14155550123. The SMS sender may instead be '
              'a registered sender ID such as SCHOOL. Enter the WhatsApp number without a "whatsapp:" prefix - '
              'the app adds it.',
              style: muted,
            ),
            for (final field in settings.fields) ...[const SizedBox(height: 12), _credentialInput(field)],
            if (_serverError('credentials') != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(_serverError('credentials')!, style: TextStyle(fontSize: 12, color: colors.danger)),
              ),
          ],
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: colors.danger))],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('messaging-save'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
              for (final channel in MessagingChannel.values)
                OutlinedButton.icon(
                  key: Key('messaging-test-${channel.apiValue}'),
                  onPressed: _saving ? null : () => _openTestDialog(channel),
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text('Send test ${channel.label}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// One setting's box, what is saved for it, and a way to remove it.
  Widget _credentialInput(MessagingCredentialField field) {
    final clearing = _clearing.contains(field.key);
    final helper = clearing
        ? 'The saved value will be removed when you save.'
        : !field.isSet
        ? null
        : field.secret || field.hint == null
        ? 'Saved - leave empty to keep'
        : 'Saved: ${field.hint} - leave empty to keep';
    final key = Key('messaging-${field.key}');

    final input = field.secret
        ? PasswordField(
            key: key,
            controller: _controllers[field.key]!,
            label: field.label,
            helperText: helper,
            // Any value, or none - this is a key from Twilio, not a password
            // being chosen.
            validator: (_) => null,
          )
        : TextFormField(
            key: key,
            controller: _controllers[field.key],
            decoration: InputDecoration(labelText: field.label, helperText: helper),
            validator: _senderNumberKeys.contains(field.key) ? (v) => _senderNumberProblem(field.key, v) : null,
          );

    if (!field.isSet) return input;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        input,
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: Key('messaging-clear-${field.key}'),
            onPressed: _saving
                ? null
                : () => setState(() => clearing ? _clearing.remove(field.key) : _clearing.add(field.key)),
            child: Text(clearing ? 'Keep the saved ${field.label}' : 'Remove the saved ${field.label}'),
          ),
        ),
      ],
    );
  }
}

/// A WhatsApp sender is a number in full international form, without the
/// `whatsapp:` prefix the server adds itself. An SMS sender may be that, or
/// an alphanumeric sender ID - India's DLT-registered headers, for one, are
/// letters ("SCHOOL"), and Twilio takes them as the From. Empty is fine: it
/// keeps what is saved.
String? _senderNumberProblem(String key, String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;

  if (key == 'whatsapp_from' && text.toLowerCase().startsWith('whatsapp:')) {
    return 'Leave out "whatsapp:" - the app adds it';
  }

  final isNumber = RegExp(r'^\+[0-9]{8,15}$').hasMatch(text.replaceAll(' ', ''));
  if (isNumber) return null;

  if (key == 'sms_from') {
    final isSenderId = RegExp(r'^[A-Za-z0-9]{3,11}$').hasMatch(text) && RegExp('[A-Za-z]').hasMatch(text);
    return isSenderId ? null : 'Use the full international form, like +14155550123, or a sender ID of up to 11 letters';
  }

  return 'Use the full international form, like +14155550123';
}

/// Which provider is in use, how the last test went, and who last saved.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.settings});

  final PlatformMessaging settings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = TextStyle(fontSize: 13, color: colors.muted);
    final lastTest = settings.lastTestedAtLabel ?? settings.lastTestedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!settings.isSaved) Text('Not saved yet - messages go through the Demo Gateway.', style: muted),
        if (lastTest != null) Text('Last tested $lastTest', style: muted),
        if (lastTest != null && settings.lastTestError == null) Text('Last test succeeded', style: muted),
        if (settings.lastTestError != null)
          Text('Last test failed: ${settings.lastTestError}', style: TextStyle(fontSize: 13, color: colors.danger)),
        if (settings.updatedByName != null) Text('Updated by ${settings.updatedByName}', style: muted),
      ],
    );
  }
}

/// Asks for a number, sends the test, and pops with the server's message on
/// success. A refusal stays in the dialog in the provider's own words, so the
/// number can be corrected or the account looked at.
class _TestMessageDialog extends ConsumerStatefulWidget {
  const _TestMessageDialog({required this.channel});

  final MessagingChannel channel;

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
    if (_sending || !_formKey.currentState!.validate()) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final message = await ref
          .read(platformMessagingNotifierProvider.notifier)
          .sendTest(widget.channel, _toController.text.trim());
      if (mounted) Navigator.of(context).pop(message);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send test ${widget.channel.label}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Uses the account as it is saved, not what is typed on the form.'),
              const SizedBox(height: 12),
              PhoneNumberField(
                key: const Key('messaging-test-to'),
                controller: _toController,
                label: 'Send to',
                required: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: context.appColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
