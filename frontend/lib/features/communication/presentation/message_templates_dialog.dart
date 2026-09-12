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
          ],
        ),
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
