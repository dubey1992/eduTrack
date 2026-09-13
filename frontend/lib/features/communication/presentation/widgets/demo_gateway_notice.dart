import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/message_page_notifier.dart';

/// Says plainly that no text is leaving the building.
///
/// Until a real SMS provider is configured, messages are written to a log and
/// recorded as "Sent". That is exactly right for a demo and dangerous
/// everywhere else: a school that reads "Sent" next to a parent's name will
/// believe the parent was told. This appears wherever the app makes that
/// claim, and disappears on its own the moment a real gateway is configured.
class DemoGatewayNotice extends ConsumerWidget {
  const DemoGatewayNotice({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(messageSummaryProvider(schoolId)).value;

    // Nothing is shown while the summary is loading or if it failed: a
    // missing answer is not evidence of a demo gateway.
    if (summary == null || summary.providerDelivers) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.errorContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No text messages are being delivered',
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'This school is on ${summary.providerLabel ?? 'a demo gateway'}, which records '
                      'messages without sending them. Anything marked Sent below reached the log, '
                      'not a phone. Connect a real SMS provider before relying on alerts.',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
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
