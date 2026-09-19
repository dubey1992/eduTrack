import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/trip_mark_queue.dart';

/// "6 marks" / "1 mark".
String marksLabel(int count) => '$count ${count == 1 ? 'mark' : 'marks'}';

/// The strip at the top of My Trip saying what has not reached the server
/// yet: "Offline - 6 marks waiting to send", "Sending 6 marks...", or nothing
/// at all once everything is sent.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(tripMarkQueueProvider);
    final count = queue.pendingCount;
    if (count == 0) return const SizedBox.shrink();

    final colors = context.appColors;
    final (text, background, foreground) = queue.sending
        ? ('Sending ${marksLabel(count)}...', colors.infoContainer, colors.onInfoContainer)
        : queue.offline
        ? ('Offline - ${marksLabel(count)} waiting to send', colors.warningContainer, colors.onWarningContainer)
        : ('${marksLabel(count)} waiting to send', colors.infoContainer, colors.onInfoContainer);

    return Material(
      key: const Key('my-trip-sync-banner'),
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (queue.sending)
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: foreground))
            else
              Icon(queue.offline ? Icons.cloud_off : Icons.cloud_upload_outlined, size: 18, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
              ),
            ),
            if (!queue.sending)
              TextButton(
                onPressed: () => ref.read(tripMarkQueueProvider.notifier).retryNow(),
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: const Text('Send now'),
              ),
          ],
        ),
      ),
    );
  }
}
