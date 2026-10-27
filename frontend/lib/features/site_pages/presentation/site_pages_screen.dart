import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/site_page_notifiers.dart';
import '../data/models/site_page.dart';
import 'site_page_editor.dart';
import 'site_page_links.dart';

/// Website Pages: About Us, Privacy Policy, Terms of Use and any page the
/// Super Admin adds (docs/site-pages.md). Super Admin only - the API refuses
/// everyone else, and the nav item is not shown to them.
///
/// The list and the editor share one route, `/site-pages`, with the page
/// being edited in the query (`?page=terms`, or `?new=1`), so the sidebar's
/// Super Admin check covers the editor too.
class SitePagesScreen extends StatelessWidget {
  const SitePagesScreen({super.key, this.editing, this.creating = false});

  /// The slug of the page open in the editor, if any.
  final String? editing;
  final bool creating;

  @override
  Widget build(BuildContext context) {
    if (creating) return const SitePageEditor(key: ValueKey('new'));

    final editing = this.editing;
    if (editing != null) return SitePageEditor(key: ValueKey(editing), slug: editing);

    return const _PageList();
  }
}

class _PageList extends ConsumerWidget {
  const _PageList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(sitePageListNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Website Pages',
          actions: [
            FilledButton.icon(
              onPressed: () => context.go('/site-pages?new=1'),
              icon: const Icon(Icons.add),
              label: const Text('New Page'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Pages anyone can read without signing in. Link to one from the homepage footer '
            '(Homepage Content) using its address, such as /terms.',
            style: TextStyle(color: context.appColors.muted),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncValueView<List<SitePageSummary>>(
            value: pages,
            onRetry: () => ref.read(sitePageListNotifierProvider.notifier).load(),
            data: (context, pages) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: pages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _PageCard(page: pages[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageCard extends ConsumerStatefulWidget {
  const _PageCard({required this.page});

  final SitePageSummary page;

  @override
  ConsumerState<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends ConsumerState<_PageCard> {
  bool _deleting = false;

  Future<void> _delete() async {
    final page = widget.page;
    final confirmed = await confirmDialog(
      context,
      title: 'Delete "${page.title}"?',
      message: page.isLive
          ? 'The page is taken off ${publicAddress(page.slug)} at once, and links to it will show "not available". '
                'This cannot be undone.'
          : 'The draft is deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(sitePageListNotifierProvider.notifier).delete(page.slug);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('"${page.title}" deleted.')));
    } catch (error) {
      final message = error is Failure ? error.message : 'The page could not be deleted. Please try again.';
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final muted = context.appColors.muted;
    final publishedAt = page.publishedAt;

    final (status, tone) = switch (page) {
      SitePageSummary(isLive: false) => ('Not published', BadgeTone.warning),
      SitePageSummary(hasUnpublishedChanges: true) => ('Live · changes not published', BadgeTone.info),
      _ => ('Live', BadgeTone.success),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(page.title, style: Theme.of(context).textTheme.titleMedium),
                      StatusBadge(label: status, tone: tone),
                      if (page.builtIn) const StatusBadge(label: 'Built-in', tone: BadgeTone.neutral),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      publicAddress(page.slug),
                      if (publishedAt != null) 'Published ${formatDate(publishedAt)}',
                    ].join(' · '),
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (page.isLive)
                  TextButton.icon(
                    onPressed: () => openPublishedPage(page.slug),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('View'),
                  ),
                OutlinedButton.icon(
                  onPressed: _deleting ? null : () => context.go('/site-pages?page=${page.slug}'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                if (!page.builtIn)
                  IconButton(
                    onPressed: _deleting ? null : _delete,
                    tooltip: 'Delete page',
                    icon: _deleting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.delete_outline, color: context.appColors.danger),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
