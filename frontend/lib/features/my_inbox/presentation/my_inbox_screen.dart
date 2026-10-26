import '../../../core/widgets/period_filter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../communication/data/models/message.dart';
import '../application/my_inbox_notifier.dart';

/// The School365ai app's inbox (docs/teacher-app.md, T4), opened from the
/// bell: what the school sent this person, newest first. Opening a message
/// shows it whole and marks it read.
class MyInboxScreen extends ConsumerWidget {
  const MyInboxScreen({super.key});

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      final marked = await ref.read(myInboxProvider.notifier).markAllRead();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(marked == 0 ? 'Nothing was unread.' : 'Marked $marked as read.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(myInboxProvider);
    final hasUnread = inbox.value?.items.any((message) => message.isUnread) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          TextButton(
            key: const Key('inbox-read-all'),
            onPressed: hasUnread ? () => _markAllRead(context, ref) : null,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              key: const Key('inbox-refresh'),
              onRefresh: () => ref.read(myInboxProvider.notifier).refresh(),
              child: inbox.hasValue && !inbox.isLoading
                  ? _List(inbox: inbox.requireValue)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const _Filter(),
                        const SizedBox(height: 12),
                        AsyncValueView<MyInbox>(
                          value: inbox,
                          onRetry: () => ref.read(myInboxProvider.notifier).retry(),
                          data: (context, value) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Filter extends ConsumerWidget {
  const _Filter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadOnly = ref.watch(myInboxProvider).value?.unreadOnly ?? false;
    final notifier = ref.read(myInboxProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('inbox-all'),
              label: const Text('All'),
              selected: !unreadOnly,
              onSelected: (_) => notifier.setUnreadOnly(false),
            ),
            ChoiceChip(
              key: const Key('inbox-unread'),
              label: const Text('Unread'),
              selected: unreadOnly,
              onSelected: (_) => notifier.setUnreadOnly(true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PeriodFilter(value: notifier.period, onChanged: notifier.setPeriod),
      ],
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.inbox});

  final MyInbox inbox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return ListView(
      key: const Key('inbox-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const _Filter(),
        const SizedBox(height: 12),
        if (inbox.items.isEmpty)
          Padding(
            key: const Key('inbox-empty'),
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.mark_email_read_outlined, size: 48, color: colors.muted),
                const SizedBox(height: 12),
                Text(inbox.unreadOnly ? 'Nothing unread.' : 'No messages yet.', textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  'Announcements and notices from your school arrive here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted),
                ),
              ],
            ),
          )
        else ...[
          for (final message in inbox.items) _MessageTile(message: message),
          if (inbox.hasMore)
            Center(
              child: TextButton(
                key: const Key('inbox-more'),
                onPressed: () => ref.read(myInboxProvider.notifier).loadMore(),
                child: const Text('Show older messages'),
              ),
            ),
        ],
      ],
    );
  }
}

class _MessageTile extends ConsumerWidget {
  const _MessageTile({required this.message});

  final Message message;

  String get _title => (message.subject?.trim().isNotEmpty ?? false) ? message.subject! : message.eventLabel;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // Read the moment it is opened; a failure to mark it is not worth
    // keeping the message from the person.
    ref.read(myInboxProvider.notifier).markRead(message).catchError((Object error) {
      debugPrint('Marking message ${message.id} read failed: $error');
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MessageSheet(message: message, title: _title),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final unread = message.isUnread;

    return Card(
      key: Key('inbox-message-${message.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 10),
                child: Container(
                  key: unread ? Key('inbox-unread-dot-${message.id}') : null,
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread ? theme.colorScheme.primary : Colors.transparent,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(message.createdOnLabel ?? '', style: TextStyle(fontSize: 12, color: colors.muted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Text(message.category.label, style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.message, required this.title});

  final Message message;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final when = [message.createdOnLabel, message.createdAtLabel].whereType<String>().join(' · ');

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          key: const Key('inbox-message-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${message.category.label} · $when', style: TextStyle(color: colors.muted)),
              if (message.studentName != null) ...[
                const SizedBox(height: 4),
                Text('About ${message.studentName}', style: TextStyle(color: colors.muted)),
              ],
              const SizedBox(height: 16),
              SelectableText(message.body, style: const TextStyle(fontSize: 16, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}
