import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/section_header.dart';
import '../application/mail_settings_notifier.dart';
import '../data/models/mail_settings.dart';

/// The SMTP server the platform sends through. Super Admin only - the API
/// refuses everyone else, and the nav item is not shown to them.
class MailSettingsScreen extends ConsumerWidget {
  const MailSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(mailSettingsNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Email Settings'),
        Expanded(
          child: AsyncValueView<MailSettings>(
            value: settingsState,
            onRetry: () => ref.read(mailSettingsNotifierProvider.notifier).load(),
            data: (context, settings) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _MailSettingsForm(settings: settings),
                    ),
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

class _MailSettingsForm extends ConsumerStatefulWidget {
  const _MailSettingsForm({required this.settings});

  final MailSettings settings;

  @override
  ConsumerState<_MailSettingsForm> createState() => _MailSettingsFormState();
}

class _MailSettingsFormState extends ConsumerState<_MailSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _hostController = TextEditingController(text: widget.settings.host);
  late final _portController = TextEditingController(text: widget.settings.port == 0 ? '' : '${widget.settings.port}');
  late final _usernameController = TextEditingController(text: widget.settings.username ?? '');
  final _passwordController = TextEditingController();
  late final _fromAddressController = TextEditingController(text: widget.settings.fromAddress);
  late final _fromNameController = TextEditingController(text: widget.settings.fromName);

  late MailEncryption _encryption = widget.settings.encryption;
  late bool _isActive = widget.settings.isActive;

  /// Set when the Super Admin asks for the stored password to be removed;
  /// the save then sends an empty password instead of leaving the key out.
  bool _clearPassword = false;

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _fromAddressController.dispose();
    _fromNameController.dispose();
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  /// What goes out as the password: nothing when the field was left alone
  /// (the stored one is kept), an empty string to clear it, or the new one.
  String? get _passwordToSend {
    if (_clearPassword) return '';
    final typed = _passwordController.text;
    return typed.isEmpty ? null : typed;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final messenger = ScaffoldMessenger.of(context);
    final username = _usernameController.text.trim();

    try {
      await ref
          .read(mailSettingsNotifierProvider.notifier)
          .save(
            isActive: _isActive,
            host: _hostController.text.trim(),
            port: int.parse(_portController.text.trim()),
            encryption: _encryption,
            username: username.isEmpty ? null : username,
            password: _passwordToSend,
            fromAddress: _fromAddressController.text.trim(),
            fromName: _fromNameController.text.trim(),
          );

      if (!mounted) return;
      // The stored password is now whatever was just sent; the field goes
      // back to meaning "keep it".
      _passwordController.clear();
      setState(() => _clearPassword = false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Email settings saved.')));
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

  Future<void> _openTestDialog() async {
    final message = await showDialog<String>(context: context, builder: (_) => const _TestEmailDialog());
    if (message == null || !mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final colors = context.appColors;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusLine(settings: settings),
          const SizedBox(height: 16),
          _FieldPair(
            left: TextFormField(
              key: const Key('mail-host'),
              controller: _hostController,
              decoration: InputDecoration(labelText: 'Host', errorText: _serverError('host')),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Host is required' : null,
            ),
            right: TextFormField(
              key: const Key('mail-port'),
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Port', errorText: _serverError('port')),
              validator: (v) {
                final port = int.tryParse((v ?? '').trim());
                if (port == null || port < 1 || port > 65535) return 'Port must be between 1 and 65535';
                return null;
              },
            ),
          ),
          const SizedBox(height: 12),
          _FieldPair(
            left: DropdownButtonFormField<MailEncryption>(
              key: const Key('mail-encryption'),
              initialValue: _encryption,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Encryption', errorText: _serverError('encryption')),
              items: [
                for (final option in MailEncryption.values) DropdownMenuItem(value: option, child: Text(option.label)),
              ],
              onChanged: (value) => setState(() => _encryption = value ?? _encryption),
            ),
            right: TextFormField(
              key: const Key('mail-username'),
              controller: _usernameController,
              decoration: InputDecoration(labelText: 'Username', errorText: _serverError('username')),
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(
            key: const Key('mail-password'),
            controller: _passwordController,
            helperText: _clearPassword
                ? 'The saved password will be removed when you save.'
                : settings.passwordSet
                ? 'Leave blank to keep the saved password'
                : null,
            // Any password, or none - this is not a password being chosen.
            validator: (_) => null,
          ),
          if (_serverError('password') != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(_serverError('password')!, style: TextStyle(fontSize: 12, color: colors.danger)),
            ),
          if (settings.passwordSet)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('mail-clear-password'),
                onPressed: () => setState(() => _clearPassword = !_clearPassword),
                child: Text(_clearPassword ? 'Keep the saved password' : 'Remove the saved password'),
              ),
            ),
          const SizedBox(height: 12),
          _FieldPair(
            left: TextFormField(
              key: const Key('mail-from-address'),
              controller: _fromAddressController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: 'From address', errorText: _serverError('from_address')),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return 'From address is required';
                if (!text.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            right: TextFormField(
              key: const Key('mail-from-name'),
              controller: _fromNameController,
              decoration: InputDecoration(labelText: 'From name', errorText: _serverError('from_name')),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'From name is required' : null,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('mail-is-active'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Use these settings'),
            subtitle: const Text("Off: the server's environment settings are used"),
            value: _isActive,
            onChanged: _saving ? null : (value) => setState(() => _isActive = value),
          ),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: colors.danger))],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _openTestDialog,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Send test email'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the values in use come from, and how the last test went.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.settings});

  final MailSettings settings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = TextStyle(fontSize: 13, color: colors.muted);
    final lastTest = settings.lastTestedAtLabel ?? settings.lastTestedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source: ${settings.source}', style: muted),
        if (lastTest != null) Text('Last tested $lastTest', style: muted),
        if (settings.lastTestError != null)
          Text('Last test failed: ${settings.lastTestError}', style: TextStyle(fontSize: 13, color: colors.danger)),
        if (settings.updatedByName != null) Text('Updated by ${settings.updatedByName}', style: muted),
      ],
    );
  }
}

/// Two fields side by side where there is room, stacked where there is not.
class _FieldPair extends StatelessWidget {
  const _FieldPair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// Asks for an address, sends the test, and pops with the server's message
/// on success. A failure stays in the dialog with the server's reason, so
/// the address can be corrected or the settings looked at.
class _TestEmailDialog extends ConsumerStatefulWidget {
  const _TestEmailDialog();

  @override
  ConsumerState<_TestEmailDialog> createState() => _TestEmailDialogState();
}

class _TestEmailDialogState extends ConsumerState<_TestEmailDialog> {
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
      final message = await ref.read(mailSettingsNotifierProvider.notifier).sendTest(_toController.text.trim());
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
      title: const Text('Send test email'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Uses the settings as they are saved, not what is typed on the form.'),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('mail-test-to'),
                controller: _toController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Send to'),
                onFieldSubmitted: (_) => _send(),
                validator: (v) => (v == null || !v.trim().contains('@')) ? 'Enter a valid email' : null,
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
