import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/school_clock_provider.dart';
import '../data/models/message.dart';
import 'communication_screen.dart' show MessageStatusBadge, formatMessageTime, messageTimeOf;

/// One message in full: who it went to, what it said, and what became of it.
class MessageDetailDialog extends ConsumerWidget {
  const MessageDetailDialog({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return AlertDialog(
      title: const Text('Message details'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 420, maxWidth: 480, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(message.eventLabel, style: Theme.of(context).textTheme.titleMedium),
                  MessageStatusBadge(status: message.status),
                ],
              ),
              const SizedBox(height: 12),
              _Row(label: 'To', value: message.recipientName),
              if (message.recipientMobile != null) _Row(label: 'Mobile', value: message.recipientMobile!),
              if (message.studentName != null) _Row(label: 'Student', value: message.studentName!),
              _Row(label: 'Channel', value: message.channel.label),
              _Row(label: 'Category', value: message.category.label),
              _Row(label: 'Created', value: messageTimeOf(message, ref.watch(schoolClockProvider))),
              if (message.sentAt != null)
                _Row(label: 'Sent', value: formatMessageTime(message.createdOnLabel, message.sentAtLabel)),
              if (message.provider != null) _Row(label: 'Gateway', value: message.providerLabel ?? message.provider!),
              const SizedBox(height: 12),
              Text('Message', style: muted),
              const SizedBox(height: 4),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(message.body)),
              ),
              if (message.failureReason != null) ...[
                const SizedBox(height: 12),
                Text(message.status == MessageStatus.skipped ? 'Why it was not sent' : 'Why it failed', style: muted),
                const SizedBox(height: 4),
                Text(message.failureReason!),
              ],
            ],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
