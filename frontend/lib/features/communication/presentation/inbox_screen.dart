import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../application/inbox_notifier.dart';
import '../data/models/message.dart';
import 'communication_screen.dart' show messageTimeOf;

/// Every user's own in-app messages - today that means leave decisions, and
/// whatever later phases send them.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  @override
  void initState() {
    super.initState();
    // Messages (and announcement deletions) happen while this screen is
    // closed, so re-entering it re-reads rather than showing what was here
    // last time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only on re-entry - see the note on the other screens.
      if (!mounted || ref.read(inboxNotifierProvider) is! AsyncData) return;
      ref.read(inboxNotifierProvider.notifier).refresh();
      ref.invalidate(unreadCountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inboxState = ref.watch(inboxNotifierProvider);
    final unreadOnly = ref.watch(inboxNotifierProvider.notifier).unreadOnly;
    final unread = ref.watch(unreadCountProvider).value ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('My Inbox', style: Theme.of(context).textTheme.headlineSmall),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Unread only'),
                    selected: unreadOnly,
                    onSelected: (value) => ref.read(inboxNotifierProvider.notifier).setUnreadOnly(value),
                  ),
                  OutlinedButton(onPressed: unread == 0 ? null : _markAllRead, child: const Text('Mark all read')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            unread == 0 ? 'Nothing unread.' : '$unread unread message${unread == 1 ? '' : 's'}.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          AsyncValueView<PagedList<Message>>(
            value: inboxState,
            onRetry: () => ref.read(inboxNotifierProvider.notifier).refresh(),
            data: (context, page) => _InboxList(page: page),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final marked = await ref.read(inboxNotifierProvider.notifier).markAllRead();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$marked message${marked == 1 ? '' : 's'} marked read.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _InboxList extends ConsumerWidget {
  const _InboxList({required this.page});

  final PagedList<Message> page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No messages yet.')),
        ),
      );
    }

    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in page.items)
          Card(
            child: ListTile(
              leading: Icon(
                message.isUnread ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                color: message.isUnread ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(
                message.subject ?? message.eventLabel,
                style: TextStyle(fontWeight: message.isUnread ? FontWeight.w700 : FontWeight.w500),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.body),
                  const SizedBox(height: 4),
                  Text(messageTimeOf(message), style: muted),
                ],
              ),
              trailing: message.isUnread
                  ? TextButton(
                      onPressed: () => ref.read(inboxNotifierProvider.notifier).markRead(message),
                      child: const Text('Mark read'),
                    )
                  : null,
              isThreeLine: true,
            ),
          ),
        const SizedBox(height: 12),
        PaginationControls(
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
          perPage: page.perPage,
          onPageChanged: (value) => ref.read(inboxNotifierProvider.notifier).goToPage(value),
          onPerPageChanged: (value) => ref.read(inboxNotifierProvider.notifier).setPerPage(value),
        ),
      ],
    );
  }
}
