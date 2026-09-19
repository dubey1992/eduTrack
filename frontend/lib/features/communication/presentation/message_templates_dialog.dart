import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/async_value_view.dart';
import '../application/template_notifier.dart';
import '../data/models/message.dart';

/// The prototype's "Message Templates" manager: every automatic message,
/// what it currently says, and the placeholders it may use.
class MessageTemplatesDialog extends ConsumerWidget {
  const MessageTemplatesDialog({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesState = ref.watch(templateNotifierProvider(schoolId));

    return AlertDialog(
      title: const Text('Message Templates'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 560, maxWidth: 560, maxHeight: 560),
        child: SingleChildScrollView(
          child: AsyncValueView<List<MessageTemplate>>(
            value: templatesState,
            onRetry: () => ref.invalidate(templateNotifierProvider(schoolId)),
            data: (context, templates) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final template in templates) _TemplateTile(template: template, schoolId: schoolId)],
            ),
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template, required this.schoolId});

  final MessageTemplate template;
  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final mapping = template.whatsapp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(template.eventLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${template.category.label} · ${template.channels.map((c) => c.label).join(', ')}', style: muted),
                if (template.isCustom) const Chip(label: Text('Custom'), visualDensity: VisualDensity.compact),
                if (template.isManual) const Chip(label: Text('Written by hand'), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 6),
            Text(template.body),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EditTemplateDialog(template: template, schoolId: schoolId),
                  ),
                  child: const Text('Edit'),
                ),
                if (template.isCustom)
                  TextButton(
                    onPressed: () =>
                        ref.read(templateNotifierProvider(schoolId).notifier).resetToDefault(template.event),
                    child: const Text('Use default'),
                  ),
              ],
            ),
            if (template.channels.contains(MessageChannel.whatsapp)) ...[
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('WhatsApp template'),
                subtitle: Text(
                  mapping == null ? 'Not mapped' : '${mapping.templateName} (${mapping.language})',
                  style: muted,
                ),
                children: [
                  _WhatsappTemplateForm(
                    key: ValueKey('${template.event}-${mapping?.templateName}-${mapping?.updatedAt}'),
                    template: template,
                    schoolId: schoolId,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which of the school's approved WhatsApp templates carries one event, and
/// which placeholders fill its numbered parameters, in order.
class _WhatsappTemplateForm extends ConsumerStatefulWidget {
  const _WhatsappTemplateForm({super.key, required this.template, required this.schoolId});

  final MessageTemplate template;
  final int? schoolId;

  @override
  ConsumerState<_WhatsappTemplateForm> createState() => _WhatsappTemplateFormState();
}

class _WhatsappTemplateFormState extends ConsumerState<_WhatsappTemplateForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.template.whatsapp?.templateName ?? '',
  );
  late final TextEditingController _languageController = TextEditingController(
    text: widget.template.whatsapp?.language ?? 'en',
  );
  late final List<String> _parameters = [...?widget.template.whatsapp?.parameters];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String confirmation) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(confirmation)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(templateNotifierProvider(widget.schoolId).notifier);
    await _run(
      () => notifier.saveWhatsapp(
        widget.template.event,
        templateName: _nameController.text.trim(),
        language: _languageController.text.trim().isEmpty ? 'en' : _languageController.text.trim(),
        parameters: List.of(_parameters),
      ),
      'WhatsApp template for ${widget.template.eventLabel} saved.',
    );
  }

  Future<void> _clear() async {
    final notifier = ref.read(templateNotifierProvider(widget.schoolId).notifier);
    await _run(
      () => notifier.clearWhatsapp(widget.template.event),
      'WhatsApp template for ${widget.template.eventLabel} cleared.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WhatsApp only delivers templates approved by your provider; map each message to one.', style: muted),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Template name'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Enter the template name your provider approved.';
                    if (text.length > 120) return 'Keep the template name under 120 characters.';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _languageController,
                  decoration: const InputDecoration(labelText: 'Language'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    if (!RegExp(r'^[a-z]{2,3}(_[A-Za-z]{2,4})?$').hasMatch(text)) {
                      return 'Use a code such as en or en_US.';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Parameters, in order:', style: muted),
          const SizedBox(height: 4),
          if (_parameters.isEmpty)
            Text('None yet - tap a placeholder below to add it.', style: muted)
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _parameters.length; i++)
                  InputChip(
                    label: Text('${i + 1}. {${_parameters[i]}}'),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(() => _parameters.removeAt(i)),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text('Add a placeholder:', style: muted),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final token in widget.template.tokens)
                ActionChip(
                  label: Text('{$token}'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _parameters.add(token)),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save mapping')),
              if (widget.template.whatsapp != null)
                TextButton(onPressed: _busy ? null : _clear, child: const Text('Clear mapping')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rewords one event. The placeholder list is the server's, so a template can
/// never reference data the sender does not have.
class EditTemplateDialog extends ConsumerStatefulWidget {
  const EditTemplateDialog({super.key, required this.template, required this.schoolId});

  final MessageTemplate template;
  final int? schoolId;

  @override
  ConsumerState<EditTemplateDialog> createState() => _EditTemplateDialogState();
}

class _EditTemplateDialogState extends ConsumerState<EditTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bodyController = TextEditingController(text: widget.template.body);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await ref
          .read(templateNotifierProvider(widget.schoolId).notifier)
          .save(widget.template.event, _bodyController.text.trim());
      navigator.pop();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${widget.template.eventLabel} updated.')));
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

    return AlertDialog(
      title: Text('Edit: ${widget.template.eventLabel}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 460),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _bodyController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Enter the message to send.';
                  if (text.length < 10) return 'This message is too short to be useful.';
                  if (text.length > 480) return 'Keep the message under 480 characters.';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Text('Placeholders you can use:', style: muted),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final token in widget.template.tokens)
                    ActionChip(
                      label: Text('{$token}'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _bodyController.text = '${_bodyController.text}{$token}',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Default: ${widget.template.defaultBody}', style: muted),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
