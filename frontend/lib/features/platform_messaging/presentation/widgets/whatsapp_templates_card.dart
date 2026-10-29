import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../application/platform_messaging_notifier.dart';
import '../../data/models/platform_messaging.dart';

/// The server refuses more than this many parameters on one template.
const _maxParameters = 10;

/// What a template's language must look like, as the server checks it:
/// "en", or "en_US".
final _languageCode = RegExp(r'^[a-z]{2,3}(_[A-Za-z]{2,4})?$');

/// Every message that can go out by WhatsApp, and the approved Twilio
/// template that carries it. WhatsApp only delivers templates Meta has
/// approved, so a message with none mapped is simply not sent by WhatsApp.
class WhatsappTemplatesCard extends ConsumerStatefulWidget {
  const WhatsappTemplatesCard({super.key, required this.events});

  final List<WhatsappTemplateEvent> events;

  @override
  ConsumerState<WhatsappTemplatesCard> createState() => _WhatsappTemplatesCardState();
}

class _WhatsappTemplatesCardState extends ConsumerState<WhatsappTemplatesCard> {
  /// The event being cleared, so its buttons cannot be pressed twice.
  String? _clearing;

  Future<void> _edit(WhatsappTemplateEvent event) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TemplateDialog(event: event),
    );
    if (saved != true || !mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('WhatsApp template saved.')));
  }

  Future<void> _clear(WhatsappTemplateEvent event) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Clear template',
      message: 'WhatsApp copies of "${event.eventLabel}" will be skipped until a template is mapped again.',
      confirmLabel: 'Clear',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearing = event.event);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(platformMessagingNotifierProvider.notifier).clearTemplate(event.event);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('WhatsApp template cleared.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _clearing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 13, color: context.appColors.muted);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('WhatsApp templates', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'WhatsApp only delivers templates Meta has approved. Map each message to its Twilio Content SID; '
              'its numbered parameters are filled from the placeholders you choose, in order.',
              style: muted,
            ),
            const SizedBox(height: 8),
            if (widget.events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No message goes out by WhatsApp yet.', style: muted),
              ),
            for (final (index, event) in widget.events.indexed) ...[
              if (index > 0) const Divider(height: 1),
              _TemplateRow(
                event: event,
                busy: _clearing == event.event,
                onEdit: () => _edit(event),
                onClear: () => _clear(event),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.event, required this.busy, required this.onEdit, required this.onClear});

  final WhatsappTemplateEvent event;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = TextStyle(fontSize: 13, color: colors.muted);
    final template = event.template;

    return Padding(
      key: Key('template-row-${event.event}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.eventLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                if (template == null)
                  Text(
                    'Not mapped — WhatsApp copies of this message are skipped',
                    style: TextStyle(fontSize: 13, color: colors.warning),
                  )
                else ...[
                  Text('${template.templateName} · ${template.language}', style: muted),
                  Text(
                    template.parameters.isEmpty
                        ? 'No parameters'
                        : 'Parameters: ${_numbered(template.parameters).join(', ')}',
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: Key('template-edit-${event.event}'),
                onPressed: busy ? null : onEdit,
                child: Text(template == null ? 'Map' : 'Edit'),
              ),
              if (template != null)
                TextButton(
                  key: Key('template-clear-${event.event}'),
                  onPressed: busy ? null : onClear,
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `["student_name", "date"]` as `["{{1}} student_name", "{{2}} date"]` -
/// which token fills which of the template's numbered parameters.
List<String> _numbered(List<String> parameters) {
  return [for (final (index, name) in parameters.indexed) '{{${index + 1}}} $name'];
}

/// The Content SID, its language, and which of the event's tokens fill the
/// template's parameters, chosen one after another. Pops true once saved; a
/// refusal stays in the dialog against the field it is about.
class _TemplateDialog extends ConsumerStatefulWidget {
  const _TemplateDialog({required this.event});

  final WhatsappTemplateEvent event;

  @override
  ConsumerState<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends ConsumerState<_TemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _sidController = TextEditingController(text: widget.event.template?.templateName ?? '');
  late final _languageController = TextEditingController(text: widget.event.template?.language ?? 'en');
  late final List<String> _parameters = [...?widget.event.template?.parameters];

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    _sidController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await ref
          .read(platformMessagingNotifierProvider.notifier)
          .saveTemplate(
            event: widget.event.event,
            templateName: _sidController.text.trim(),
            language: _languageController.text.trim(),
            parameters: List.of(_parameters),
          );
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = TextStyle(fontSize: 13, color: colors.muted);
    final full = _parameters.length >= _maxParameters;

    return AlertDialog(
      title: Text('WhatsApp template: ${widget.event.eventLabel}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('template-sid'),
                  controller: _sidController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Content SID',
                    helperText: 'From Twilio, e.g. HX0123456789abcdef',
                    errorText: _serverError('template_name'),
                  ),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return 'Content SID is required';
                    if (text.length > 120) return 'At most 120 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('template-language'),
                  controller: _languageController,
                  decoration: InputDecoration(
                    labelText: 'Language',
                    helperText: 'A code such as en or en_US',
                    errorText: _serverError('language'),
                  ),
                  validator: (v) => _languageCode.hasMatch((v ?? '').trim()) ? null : 'Use a code such as en or en_US',
                ),
                const SizedBox(height: 16),
                Text('Parameters, in order', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (_parameters.isEmpty)
                  Text('None chosen - the template has no parameters.', style: muted)
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (index, label) in _numbered(_parameters).indexed)
                        InputChip(
                          key: Key('template-parameter-$index'),
                          label: Text(label),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          deleteButtonTooltipMessage: 'Remove',
                          onDeleted: _saving ? null : () => setState(() => _parameters.removeAt(index)),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  full ? 'A template takes at most $_maxParameters parameters.' : 'Tap a placeholder to add it next:',
                  style: muted,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final token in widget.event.tokens)
                      ActionChip(
                        key: Key('template-token-$token'),
                        label: Text('{$token}'),
                        onPressed: _saving || full ? null : () => setState(() => _parameters.add(token)),
                      ),
                  ],
                ),
                if (_serverError('parameters') != null) ...[
                  const SizedBox(height: 6),
                  Text(_serverError('parameters')!, style: TextStyle(fontSize: 12, color: colors.danger)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: colors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('template-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
