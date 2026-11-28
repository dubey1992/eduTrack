import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/my_register/application/register_queue.dart';
import '../../features/my_teaching/application/staff_outbox.dart';
import '../network/connection_status.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';

/// The line above every page of the web app that says whether the school's
/// internet is down and what is waiting on this computer to be sent
/// (docs/offline-web.md, O1 and O3).
///
/// Takes no space at all while online with nothing waiting, so a page looks
/// exactly as it always has.
class OfflineBar extends ConsumerWidget {
  const OfflineBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectionStatusProvider);
    final me = ref.watch(authNotifierProvider).value?.id;
    final registers = ref.watch(registerQueueProvider);
    final outbox = ref.watch(staffOutboxProvider);

    final waiting =
        registers.waiting.where((r) => r.userId == me).length +
        outbox.where((i) => i.userId == me && i.refusal == null).length;
    final refused =
        registers.unsent.where((r) => r.userId == me).length +
        outbox.where((i) => i.userId == me && i.refusal != null).length;

    if (online && waiting == 0 && refused == 0) return const SizedBox.shrink();

    final colours = context.appColors;
    final String message;
    if (!online) {
      message = waiting == 0
          ? 'Offline - no connection to the school\'s server. What you save is kept on this computer and sent when the connection is back.'
          : 'Offline - $waiting saved on this computer, sent when the connection is back.';
    } else {
      message = waiting == 0
          ? 'Some work saved on this computer while offline was not accepted by the server.'
          : 'Back online - sending $waiting saved on this computer...';
    }

    return Material(
      key: const Key('offline-bar'),
      color: online ? colours.infoContainer : colours.warningContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined,
              size: 20,
              color: online ? colours.onInfoContainer : colours.onWarningContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: online ? colours.onInfoContainer : colours.onWarningContainer),
              ),
            ),
            if (refused > 0)
              TextButton(
                key: const Key('offline-bar-refused'),
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _NotSentDialog()),
                child: Text('$refused not sent - see why'),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the server turned down when it arrived, with its reason - never
/// dropped quietly.
class _NotSentDialog extends ConsumerWidget {
  const _NotSentDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authNotifierProvider).value?.id;
    final registers = ref.watch(registerQueueProvider).unsent.where((r) => r.userId == me).toList();
    final outbox = ref.watch(staffOutboxProvider).where((i) => i.userId == me && i.refusal != null).toList();
    final muted = context.appColors.muted;

    return AlertDialog(
      title: const Text('Not sent'),
      content: SizedBox(
        width: 520,
        child: registers.isEmpty && outbox.isEmpty
            ? const Text('Nothing is waiting.')
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Saved on this computer while offline, and turned down by the server when it arrived. '
                    'Check each one and enter it again if it is still needed.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 8),
                  for (final register in registers)
                    ListTile(
                      key: Key('not-sent-register-${register.clientId}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Register: ${register.classSection}, ${formatIsoDate(register.date)}'),
                      subtitle: Text(register.reason),
                      trailing: TextButton(
                        onPressed: () => ref.read(registerQueueProvider.notifier).dismiss(register.clientId),
                        child: const Text('Dismiss'),
                      ),
                    ),
                  for (final item in outbox)
                    ListTile(
                      key: Key('not-sent-${item.key}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.label),
                      subtitle: Text(item.refusal!),
                      trailing: TextButton(
                        onPressed: () => ref.read(staffOutboxProvider.notifier).dismiss(item.key),
                        child: const Text('Dismiss'),
                      ),
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
