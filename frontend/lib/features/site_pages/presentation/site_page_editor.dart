import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/site_page_notifiers.dart';
import '../data/models/site_page.dart';
import '../data/site_page_repository.dart';
import 'page_text_editing.dart';
import 'site_page_links.dart';
import 'widgets/cover_field.dart';
import 'widgets/link_dialog.dart';
import 'widgets/page_text_view.dart';

/// Lowercase letters, numbers and single hyphens - the same rule the server
/// applies, checked here so a typo is caught before the round trip.
final _slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

const _titleMax = 120;
const _summaryMax = 300;
const _bodyMax = 100000;

/// Writing one website page: an existing one by [slug], or a new one when
/// [slug] is null (docs/site-pages.md).
class SitePageEditor extends ConsumerWidget {
  const SitePageEditor({super.key, this.slug, this.newKind = SitePageKind.page});

  final String? slug;

  /// What a new one starts as. The writer can change it until it is saved.
  final SitePageKind newKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = this.slug;

    if (slug == null) return _EditorForm(page: null, newKind: newKind);

    return AsyncValueView<SitePageDetail>(
      value: ref.watch(sitePageDetailProvider(slug)),
      onRetry: () => ref.invalidate(sitePageDetailProvider(slug)),
      data: (context, page) => _EditorForm(key: ValueKey(page.slug), page: page),
    );
  }
}

class _EditorForm extends ConsumerStatefulWidget {
  const _EditorForm({super.key, required this.page, this.newKind = SitePageKind.page});

  /// Null while the page is being created.
  final SitePageDetail? page;
  final SitePageKind newKind;

  @override
  ConsumerState<_EditorForm> createState() => _EditorFormState();
}

class _EditorFormState extends ConsumerState<_EditorForm> {
  final _formKey = GlobalKey<FormState>();
  final _bodyFocus = FocusNode();

  late final _title = TextEditingController(text: widget.page?.title ?? '');
  late final _slug = TextEditingController(text: widget.page?.slug ?? '');
  late final _body = TextEditingController(text: widget.page?.body ?? '');

  /// A page, blog post or help article - chosen while creating, fixed after.
  late SitePageKind _kind = widget.page?.kind ?? widget.newKind;
  late final _summary = TextEditingController(text: widget.page?.summary ?? '');
  late final _author = TextEditingController(text: widget.page?.author ?? defaultAuthor);
  late String? _topic = widget.page?.topic;

  /// The page as the server last answered, which is what the status card
  /// describes. Replaced after every save and publish.
  late SitePageDetail? _page = widget.page;

  /// What was last saved, to tell whether there is anything unsaved.
  late var _saved = _current;

  ({String title, String slug, String body, String summary, String author, String? topic}) get _current => (
    title: _title.text,
    slug: _slug.text,
    body: _body.text,
    summary: _summary.text,
    author: _author.text,
    topic: _topic,
  );

  /// A new page's address follows its title until somebody types one.
  bool _slugTouched = false;

  /// On a narrow screen there is room for the box or the preview, not both.
  bool _previewing = false;

  bool _saving = false;
  bool _publishing = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _creating => _page == null;
  bool get _busy => _saving || _publishing;
  bool get _builtIn => _page?.builtIn ?? false;

  bool get _dirty => _current != _saved;

  /// Only a blog post or help article has a summary; only a post an author,
  /// only an article a topic. Nothing else is sent.
  PageDetails get _pageDetails => PageDetails(
    summary: _kind == SitePageKind.page ? null : _summary.text.trim(),
    author: _kind == SitePageKind.post ? _author.text.trim() : null,
    topic: _kind == SitePageKind.help ? _topic : null,
  );

  @override
  void initState() {
    super.initState();
    _title.addListener(_followTitle);
  }

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    _body.dispose();
    _summary.dispose();
    _author.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _followTitle() {
    if (!_creating || _slugTouched) return;

    final suggested = slugFromTitle(_title.text);
    if (_slug.text != suggested) _slug.text = suggested;
  }

  void _format(TextEditingValue Function(TextEditingValue value) change) {
    _body.value = change(_body.value);
    _bodyFocus.requestFocus();
  }

  Future<void> _addLink() async {
    final link = await showLinkDialog(context, words: selectedText(_body.value));
    if (link == null) return;

    _format((value) => insertLink(value, words: link.words, address: link.address));
  }

  /// Saves the form, creating the page the first time. Returns the page as
  /// the server now has it, or null when the save did not happen.
  Future<SitePageDetail?> _store() async {
    final notifier = ref.read(sitePageListNotifierProvider.notifier);
    final title = _title.text.trim();
    final slug = _slug.text.trim();

    final page = _creating
        ? await notifier.create(slug: slug, title: title, body: _body.text, kind: _kind, details: _pageDetails)
        : await notifier.save(_page!.slug, newSlug: slug, title: title, body: _body.text, details: _pageDetails);

    _saved = _current;
    return page;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final wasCreating = _creating;
    final oldSlug = _page?.slug;

    await _run(
      busy: (value) => _saving = value,
      action: () async {
        final page = await _store();
        if (page == null || !mounted) return;

        setState(() => _page = page);
        _say(
          wasCreating
              ? 'Draft saved. Nobody can see this page until you publish it.'
              : page.isLive
              ? 'Draft saved. Visitors still see the published version.'
              : 'Draft saved.',
        );

        // A new page, or a new address, is a different place in the app.
        if (wasCreating || page.slug != oldSlug) context.go('/site-pages?page=${page.slug}');
      },
    );
  }

  /// Saves first, then publishes: pressing Publish with the box full of
  /// changes means "put *this* up", not the last thing saved.
  Future<void> _publish() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final title = _title.text.trim();
    final confirmed = await confirmDialog(
      context,
      title: 'Publish "$title"?',
      message: 'Anyone opening ${publicAddress(_slug.text.trim(), kind: _kind)} will see this version straight away.',
      confirmLabel: 'Publish',
    );
    if (!confirmed || !mounted) return;

    final wasCreating = _creating;
    final oldSlug = _page?.slug;

    await _run(
      busy: (value) => _publishing = value,
      action: () async {
        final saved = await _store();
        if (saved == null) return;

        final page = await ref.read(sitePageListNotifierProvider.notifier).publish(saved.slug);
        if (!mounted) return;

        setState(() => _page = page);
        _say(
          page.websiteProblem == null
              ? 'Published. Visitors see it now at ${publicAddress(page.slug, kind: page.kind)}.'
              : 'Published, but the website copy was not updated. ${page.websiteProblem}',
        );

        if (wasCreating || page.slug != oldSlug) context.go('/site-pages?page=${page.slug}');
      },
    );
  }

  Future<void> _run({required void Function(bool) busy, required Future<void> Function() action}) async {
    setState(() {
      busy(true);
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await action();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _error = failure.message;
          _fieldErrors = {
            for (final entry in failure.validationErrors.entries)
              if (entry.value.isNotEmpty) entry.key: entry.value.join(' '),
          };
        });
      }
    } finally {
      if (mounted) setState(() => busy(false));
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _back() async {
    if (_dirty) {
      final discard = await confirmDialog(
        context,
        title: 'Leave without saving?',
        message: 'Your changes to this page have not been saved.',
        confirmLabel: 'Leave',
        isDestructive: true,
      );
      if (!discard || !mounted) return;
    }

    context.go('/site-pages');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_title, _slug, _body, _summary, _author]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(onPressed: _back, icon: const Icon(Icons.arrow_back), label: const Text('All pages')),
              const SizedBox(height: 8),
              _Status(page: _page, dirty: _dirty),
              if (_error != null) ...[const SizedBox(height: 12), _ErrorBanner(message: _error!)],
              const SizedBox(height: 16),
              _details(),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 1000 ? _sideBySide() : _oneAtATime(),
              ),
              const SizedBox(height: 20),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        if (_creating)
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What are you writing?', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                SegmentedButton<SitePageKind>(
                  key: const Key('page-kind'),
                  segments: [
                    for (final kind in SitePageKind.values) ButtonSegment(value: kind, label: Text(kind.label)),
                  ],
                  selected: {_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy ? null : (selection) => setState(() => _kind = selection.single),
                ),
              ],
            ),
          ),
        SizedBox(
          width: 480,
          child: TextFormField(
            controller: _title,
            enabled: !_busy,
            maxLength: _titleMax,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: InputDecoration(
              labelText: switch (_kind) {
                SitePageKind.page => 'Page title',
                SitePageKind.post => 'Post title',
                SitePageKind.help => 'Article title',
              },
              errorText: _fieldErrors['title'],
              errorMaxLines: 3,
            ),
            validator: (value) {
              final title = (value ?? '').trim();
              if (title.isEmpty) return 'Give the page a title.';
              if (title.length > _titleMax) return 'The title must be $_titleMax characters or fewer.';
              return null;
            },
          ),
        ),
        SizedBox(
          width: 480,
          child: TextFormField(
            controller: _slug,
            enabled: !_busy && !_builtIn,
            maxLength: 60,
            onChanged: (_) => _slugTouched = true,
            decoration: InputDecoration(
              labelText: 'Address',
              prefixText: '${Uri.base.host}/${_kind.prefix}',
              helperText: _builtIn
                  ? 'Built-in pages keep their address.'
                  : _creating
                  ? 'Lowercase letters, numbers and hyphens.'
                  : 'Changing this moves the page at once - links to the old address stop working.',
              helperMaxLines: 2,
              errorText: _fieldErrors['slug'],
              errorMaxLines: 3,
            ),
            validator: (value) {
              final slug = (value ?? '').trim();
              if (slug.length < 2) return 'Enter an address of at least 2 characters.';
              if (!_slugPattern.hasMatch(slug)) {
                return 'Use lowercase letters, numbers and single hyphens, e.g. help-center.';
              }
              return null;
            },
          ),
        ),
        if (_kind != SitePageKind.page) _summaryField(),
        if (_kind == SitePageKind.post) _authorField(),
        if (_kind == SitePageKind.help) _topicField(),
        if (_kind == SitePageKind.post) CoverField(page: _page, onChanged: (page) => setState(() => _page = page)),
      ],
    );
  }

  Widget _summaryField() {
    return SizedBox(
      width: 976,
      child: TextFormField(
        key: const Key('page-summary'),
        controller: _summary,
        enabled: !_busy,
        maxLength: _summaryMax,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        minLines: 2,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Summary',
          helperText: _kind == SitePageKind.post
              ? 'One or two sentences, shown under the title in the blog and in search results.'
              : 'One sentence, shown under the title in the help centre and in search results.',
          helperMaxLines: 2,
          errorText: _fieldErrors['summary'],
          errorMaxLines: 3,
        ),
        validator: (value) {
          final summary = (value ?? '').trim();
          if (summary.isEmpty) return 'Write a summary - it is shown under the title in the list.';
          if (summary.length > _summaryMax) return 'The summary must be $_summaryMax characters or fewer.';
          return null;
        },
      ),
    );
  }

  Widget _authorField() {
    return SizedBox(
      width: 480,
      child: TextFormField(
        key: const Key('page-author'),
        controller: _author,
        enabled: !_busy,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: 'Author',
          helperText: 'Shown as "By ..." under the title. "$defaultAuthor" if left empty.',
          errorText: _fieldErrors['author'],
        ),
      ),
    );
  }

  Widget _topicField() {
    return SizedBox(
      width: 480,
      child: DropdownButtonFormField<String>(
        key: const Key('page-topic'),
        initialValue: _topic,
        decoration: InputDecoration(
          labelText: 'Help centre topic',
          helperText: 'The section of the help centre this article is listed under.',
          errorText: _fieldErrors['topic'],
        ),
        items: [for (final (key, label) in helpTopics) DropdownMenuItem(value: key, child: Text(label))],
        validator: (value) => value == null ? 'Choose the topic this article belongs under.' : null,
        onChanged: _busy ? null : (value) => setState(() => _topic = value),
      ),
    );
  }

  Widget _toolbar() {
    final enabled = !_busy;

    Widget button(IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: enabled ? onPressed : null);
    }

    return Wrap(
      spacing: 2,
      children: [
        button(Icons.title, 'Heading', () => _format((v) => applyLinePrefix(v, '## '))),
        button(Icons.text_fields, 'Smaller heading', () => _format((v) => applyLinePrefix(v, '### '))),
        button(Icons.format_list_bulleted, 'Bullet list', () => _format((v) => applyLinePrefix(v, '- '))),
        button(Icons.format_list_numbered, 'Numbered list', () => _format((v) => applyLinePrefix(v, '1. '))),
        button(Icons.format_bold, 'Bold', () => _format((v) => wrapSelection(v, '**', 'bold text'))),
        button(Icons.link, 'Link', _addLink),
        button(Icons.horizontal_rule, 'Line across the page', () => _format(insertDivider)),
      ],
    );
  }

  Widget _textBox({double? height}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolbar(),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: TextFormField(
            controller: _body,
            focusNode: _bodyFocus,
            enabled: !_busy,
            expands: height != null,
            minLines: height == null ? 16 : null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: InputDecoration(
              alignLabelWithHint: true,
              hintText:
                  'Write or paste the page here.\n\n'
                  '## A heading\n'
                  'A paragraph. Leave a blank line before the next one.\n\n'
                  '- A bullet\n'
                  '**Bold words** and [a link](https://example.com)',
              errorText: _fieldErrors['body'],
              errorMaxLines: 5,
            ),
            validator: (value) =>
                (value ?? '').length > _bodyMax ? 'The page must be $_bodyMax characters or fewer.' : null,
          ),
        ),
      ],
    );
  }

  Widget _preview({double? height}) {
    final title = _title.text.trim();

    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        height: height,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('PREVIEW', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.appColors.muted)),
              const SizedBox(height: 8),
              Text(title.isEmpty ? 'Page title' : title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              if (_body.text.trim().isEmpty)
                Text('Nothing written yet.', style: TextStyle(color: context.appColors.muted))
              else
                PageTextView(text: _body.text, followLinks: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideBySide() {
    const height = 620.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _textBox(height: height)),
        const SizedBox(width: 20),
        // Lined up with the box rather than the toolbar above it.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 44),
            child: _preview(height: height),
          ),
        ),
      ],
    );
  }

  Widget _oneAtATime() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.edit_outlined), label: Text('Write')),
            ButtonSegment(value: true, icon: Icon(Icons.visibility_outlined), label: Text('Preview')),
          ],
          selected: {_previewing},
          onSelectionChanged: (selected) => setState(() => _previewing = selected.first),
        ),
        const SizedBox(height: 12),
        // Kept in the tree while previewing, so its validator still runs on
        // Save and the cursor is where it was on the way back.
        Offstage(offstage: _previewing, child: _textBox()),
        if (_previewing) _preview(),
      ],
    );
  }

  Widget _actions() {
    final page = _page;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Save Draft'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _publish,
          icon: _publishing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.publish_outlined),
          label: const Text('Publish'),
        ),
        if (page != null && page.isLive)
          TextButton.icon(
            onPressed: () => openPublishedPage(page.slug, kind: page.kind),
            icon: const Icon(Icons.open_in_new),
            label: const Text('View live page'),
          ),
      ],
    );
  }
}

/// A title as an address: "Help & Support" -> "help-and-support", cut to
/// the 60 characters an address may have.
String slugFromTitle(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  return slug.length <= 60 ? slug : slug.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
}

class _Status extends StatelessWidget {
  const _Status({required this.page, required this.dirty});

  final SitePageDetail? page;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final page = this.page;

    final (icon, color, heading, detail) = switch (page) {
      null => (Icons.note_add_outlined, colors.info, 'New page', 'Save a draft, then publish it when it is ready.'),
      SitePageDetail(isLive: false) => (
        Icons.edit_note,
        colors.warning,
        'Not published',
        'Nobody can see this page yet. Publish it when it is ready.',
      ),
      SitePageDetail(hasUnpublishedChanges: true) => (
        Icons.edit_note,
        colors.warning,
        'Live, with changes not yet published',
        'Visitors are reading the published version. Publish to put your changes up.',
      ),
      _ => (Icons.public, colors.success, 'Live', 'Visitors see exactly what is saved here.'),
    };
    final publishedAt = page?.publishedAt;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                  if (page != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        publicAddress(page.slug, kind: page.kind),
                        if (publishedAt != null) 'Last published ${formatDateTime(publishedAt)}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ],
                  if (dirty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'You have unsaved changes.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.warning),
                    ),
                  ],
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
