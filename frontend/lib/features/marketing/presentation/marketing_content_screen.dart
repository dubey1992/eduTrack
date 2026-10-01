import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/marketing_draft_notifier.dart';
import '../data/marketing_content.dart';
import '../data/models/marketing_draft.dart';
import 'marketing_preview_dialog.dart';
import 'widgets/marketing_list_editor.dart';

/// The words on the public homepage. Super Admin only - the API refuses
/// everyone else, and the nav item is not shown to them.
///
/// The form is drawn from what the server declares rather than written out
/// here, so a field added to the page appears in this screen without it
/// being touched (docs/marketing-content.md).
class MarketingContentScreen extends ConsumerWidget {
  const MarketingContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftState = ref.watch(marketingDraftNotifierProvider);

    // No heading of its own: the shell already puts "Homepage Content" and
    // what it is for above this, and the screen is one form rather than a
    // list with actions to hang off a SectionHeader.
    return AsyncValueView<MarketingDraft>(
      value: draftState,
      onRetry: () => ref.read(marketingDraftNotifierProvider.notifier).load(),
      data: (context, draft) => _MarketingContentForm(
        // A save replaces the draft, and the boxes must not be rebuilt around
        // the controllers while somebody is typing in them - so the form's
        // state is keyed to the load, not to every answer.
        key: ValueKey(draft.sections.length),
        draft: draft,
      ),
    );
  }
}

class _MarketingContentForm extends ConsumerStatefulWidget {
  const _MarketingContentForm({super.key, required this.draft});

  final MarketingDraft draft;

  @override
  ConsumerState<_MarketingContentForm> createState() => _MarketingContentFormState();
}

class _MarketingContentFormState extends ConsumerState<_MarketingContentForm> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};

  /// The repeating lists as they stand, by key. Seeded with what somebody
  /// saved, or the list the page ships with when they have not touched it -
  /// a list has no placeholder to show the shipped one in.
  final _lists = <String, List<Map<String, String>>>{};

  bool _saving = false;
  bool _publishing = false;
  String? _error;

  /// What the server objected to, by field key, so each box can say what
  /// is wrong with it rather than all of it piling up above the form.
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();

    for (final field in widget.draft.fields) {
      _controllers[field.key] = TextEditingController(text: widget.draft.draft[field.key] ?? '');
    }

    for (final declared in widget.draft.listFields) {
      _lists[declared.key] = widget.draft.itemsFor(declared.key);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The whole form, minus the boxes left empty - an empty box means "say
  /// what you ship with", which is a key the server does not store.
  Map<String, String> get _typed {
    final document = <String, String>{};

    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) document[entry.key] = text;
    }

    return document;
  }

  /// The form as it goes to the server: the words, and the lists beside
  /// them in the same document.
  Map<String, Object> get _document => {..._typed, ..._lists};

  bool get _busy => _saving || _publishing;

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(marketingDraftNotifierProvider.notifier).save(_document);

      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Draft saved. The homepage still shows the published words.')));
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves first, then publishes.
  ///
  /// Pressing Publish with unsaved boxes on screen clearly means "put
  /// *this* on the homepage". Publishing the last saved draft instead
  /// would be technically defensible and completely baffling.
  Future<void> _publish() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Publish the homepage?',
      message: 'Everyone visiting the site will see these words straight away.',
      confirmLabel: 'Publish',
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _publishing = true;
      _error = null;
      _fieldErrors = const {};
    });

    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(marketingDraftNotifierProvider.notifier);

    try {
      await notifier.save(_document);
      await notifier.publish();

      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Published. Visitors see the new words now.')));
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _showFailure(Object error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    if (!mounted) return;

    setState(() {
      _error = failure.message;
      _fieldErrors = _problemsByField(failure);
    });
  }

  /// The server reports every problem at once, as sentences naming the
  /// field by its label. Matching them back to the boxes lets each one be
  /// marked up where somebody can act on it.
  Map<String, String> _problemsByField(Failure failure) {
    final problems = failure.validationErrors['document'] ?? const <String>[];
    final byField = <String, String>{};

    for (final problem in problems) {
      for (final field in widget.draft.fields) {
        if (!byField.containsKey(field.key) && problem.startsWith('${field.label} ')) {
          byField[field.key] = problem;
        }
      }
    }

    return byField;
  }

  void _preview() {
    // The real homepage, drawn from the boxes as they are now - including
    // anything typed and not yet saved, which is what "preview" has to mean
    // for it to be worth pressing.
    showMarketingPreview(context, MarketingContent(_typed, _lists));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Status(draft: widget.draft),
                if (_error != null) ...[const SizedBox(height: 12), _ErrorBanner(message: _error!)],
                for (final section in widget.draft.sections) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    section: section,
                    controllers: _controllers,
                    lists: _lists,
                    fieldErrors: _fieldErrors,
                    onListChanged: (key, items) => _lists[key] = items,
                    enabled: !_busy,
                  ),
                ],
                const SizedBox(height: 20),
                _Actions(
                  saving: _saving,
                  publishing: _publishing,
                  onSave: _save,
                  onPreview: _preview,
                  onPublish: _publish,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.draft});

  final MarketingDraft draft;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final publishedAt = draft.publishedAt;
    // Never published is its own state: nothing is live, so "the homepage
    // matches this draft" would be true and useless.
    final neverPublished = publishedAt == null;
    final waiting = draft.hasUnpublishedChanges || neverPublished;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(waiting ? Icons.edit_note : Icons.public, color: waiting ? colors.warning : colors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    waiting ? 'Draft not published' : 'The homepage matches this draft',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(switch ((neverPublished, draft.hasUnpublishedChanges)) {
                    (true, false) => 'The homepage shows the words the app ships with.',
                    (true, true) => 'Nothing here is live yet. Publish when you are ready.',
                    (false, true) => 'Visitors are still reading the published words. Publish when you are ready.',
                    (false, false) => 'Everything here is what visitors see.',
                  }, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    neverPublished ? 'Never published.' : 'Last published ${formatDateTime(publishedAt)}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(message, style: TextStyle(color: colors.onDangerContainer)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.controllers,
    required this.lists,
    required this.fieldErrors,
    required this.onListChanged,
    required this.enabled,
  });

  final MarketingSection section;
  final Map<String, TextEditingController> controllers;
  final Map<String, List<Map<String, String>>> lists;
  final Map<String, String> fieldErrors;
  final void Function(String key, List<Map<String, String>> items) onListChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              section.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.appColors.muted),
            ),
            for (final field in section.fields) ...[
              const SizedBox(height: 16),
              _FieldBox(
                field: field,
                controller: controllers[field.key]!,
                serverError: fieldErrors[field.key],
                enabled: enabled,
              ),
            ],
            for (final declared in section.lists) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              MarketingListEditor(
                declared: declared,
                initial: lists[declared.key] ?? declared.shipped,
                onChanged: (items) => onListChanged(declared.key, items),
                serverError: fieldErrors[declared.key],
                enabled: enabled,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.field, required this.controller, required this.serverError, required this.enabled});

  final MarketingField field;
  final TextEditingController controller;
  final String? serverError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final help = field.help.isEmpty
        ? 'Leave empty to use: ${field.shipped}'
        : '${field.help} Leave empty to use: ${field.shipped}';

    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: field.multiline ? 4 : 1,
      // Counted rather than cut off: somebody pasting a long sentence
      // should see how far over they are, not lose the end of it silently.
      maxLength: field.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      decoration: InputDecoration(
        labelText: field.label,
        // The shipped copy, so an empty box still shows what visitors read.
        hintText: field.shipped,
        helperText: help,
        helperMaxLines: 3,
        errorText: serverError,
        errorMaxLines: 3,
      ),
      validator: (value) {
        final text = (value ?? '').trim();

        if (text.length > field.maxLength) {
          return '${field.label} must be ${field.maxLength} characters or fewer - it is ${text.length}.';
        }

        if (!field.multiline && text.contains('\n')) return '${field.label} is a single line.';

        return null;
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.saving,
    required this.publishing,
    required this.onSave,
    required this.onPreview,
    required this.onPublish,
  });

  final bool saving;
  final bool publishing;
  final VoidCallback onSave;
  final VoidCallback onPreview;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final busy = saving || publishing;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onSave,
          icon: saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Save Draft'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onPreview,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onPublish,
          icon: publishing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.publish_outlined),
          label: const Text('Publish'),
        ),
      ],
    );
  }
}
