import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../data/battery_guard.dart';
import '../data/trip_health_log.dart';

/// Hands the report to the phone's share sheet. A provider so a test can
/// see what would have been shared.
typedef ShareText = Future<void> Function(String text);

final shareTextProvider = Provider<ShareText>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: 'School365ai Bus - trip check'));
  },
);

/// The last trip's log, newest read.
final tripHealthEventsProvider = FutureProvider.autoDispose<List<TripHealthEvent>>(
  (ref) => ref.read(tripHealthLogProvider).events(),
);

/// "Did this phone keep sharing with the screen off?" (docs/mobile-apps-
/// review.md, M0). For the real-phone test on Xiaomi, Oppo, Vivo and
/// Samsung - and for any school whose map shows a bus that keeps
/// vanishing. It reads the log the trip itself keeps; nothing is sent
/// anywhere unless somebody shares the report.
class TripCheckScreen extends ConsumerWidget {
  const TripCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(tripHealthEventsProvider);
    final mayStop = ref.watch(phoneMayStopSharingProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.busTripCheck)),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.busTripLogUnreadable)),
        data: (list) {
          final summary = TripHealthSummary.of(list);
          final exempt = mayStop.value == null ? null : !mayStop.value!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PhoneCard(exempt: exempt),
              const SizedBox(height: 12),
              if (summary == null)
                Card(
                  child: Padding(padding: const EdgeInsets.all(16), child: Text(l10n.busTripCheckNone)),
                )
              else
                _SummaryCard(summary: summary),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('trip-check-share'),
                onPressed: () => ref.read(shareTextProvider)(reportText(summary, exempt: exempt, at: DateTime.now())),
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.busShareReport),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('trip-check-clear'),
                onPressed: summary == null
                    ? null
                    : () async {
                        await ref.read(tripHealthLogProvider).clear();
                        ref.invalidate(tripHealthEventsProvider);
                      },
                child: Text(l10n.busClearLog),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.exempt});

  final bool? exempt;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final l10n = context.l10n;

    return Card(
      child: ListTile(
        key: const Key('trip-check-battery'),
        leading: Icon(
          exempt == true ? Icons.battery_full : Icons.battery_alert,
          color: exempt == true ? colours.success : colours.warning,
        ),
        title: Text(switch (exempt) {
          true => l10n.busBatteryExempt,
          false => l10n.busBatteryMayStop,
          null => l10n.busBatteryChecking,
        }),
        subtitle: Text(l10n.busBatteryOwnSetting),
        trailing: TextButton(onPressed: () => context.push('/battery'), child: Text(l10n.busSteps)),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final TripHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final time = DateFormat('h:mm a');
    final gapColour = summary.hadWorryingGap ? colours.danger : colours.success;
    final l10n = context.l10n;

    Widget row(String label, String value, {Color? colour, Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            key: key,
            style: TextStyle(fontWeight: FontWeight.w700, color: colour),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.busLastTrip, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${DateFormat('MMM d').format(summary.from)}, ${time.format(summary.from)} - ${time.format(summary.to)}',
              style: TextStyle(color: colours.muted),
            ),
            const SizedBox(height: 8),
            row(l10n.busPositionsTaken, '${summary.points}'),
            row(l10n.busLongestGap, _minutes(summary.longestGap), colour: gapColour, key: const Key('trip-check-gap')),
            row(l10n.busSentToSchool, '${summary.sent}'),
            row(l10n.busStillWaiting, '${summary.stillWaiting}'),
            if (summary.refused > 0) row(l10n.busRefused, '${summary.refused}', colour: colours.danger),
            if (summary.cleared > 0) row(l10n.busDroppedAfterEnd, '${summary.cleared}', colour: colours.warning),
            row(l10n.busBackgrounded, '${summary.backgrounded}'),
            const SizedBox(height: 8),
            Text(
              summary.hadWorryingGap
                  ? l10n.busGapVerdict(_minutes(summary.longestGap), time.format(summary.longestGapAt!))
                  : l10n.busNoGapVerdict,
              key: const Key('trip-check-verdict'),
              style: TextStyle(color: gapColour, fontWeight: FontWeight.w600),
            ),
            for (final reason in summary.stops) ...[
              const SizedBox(height: 4),
              Text(l10n.busSharingStopped(reason), style: TextStyle(color: colours.muted, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

String _minutes(Duration gap) {
  if (gap < const Duration(minutes: 1)) return '${gap.inSeconds} s';

  return '${gap.inMinutes} min ${gap.inSeconds % 60} s';
}

/// The report a tester shares - plain text, so it reads the same in
/// WhatsApp, email or a note. No positions and no names.
String reportText(TripHealthSummary? summary, {required bool? exempt, required DateTime at}) {
  final lines = [
    'School365ai Bus - trip check, ${DateFormat('MMM d, y h:mm a').format(at)}',
    'Battery saving exemption: ${switch (exempt) {
      true => 'yes',
      false => 'no',
      null => 'unknown',
    }}',
  ];

  if (summary == null) {
    lines.add('No trip has shared its location on this phone yet.');
  } else {
    final time = DateFormat('h:mm a');
    lines.addAll([
      'Trip ${summary.tripId}: ${time.format(summary.from)} - ${time.format(summary.to)}',
      'Positions taken: ${summary.points}',
      'Longest gap: ${_minutes(summary.longestGap)}'
          '${summary.longestGapAt == null ? '' : ' (from ${time.format(summary.longestGapAt!)})'}',
      'Sent: ${summary.sent}, still waiting: ${summary.stillWaiting}, refused: ${summary.refused}, '
          'dropped after the end: ${summary.cleared}',
      'Times in the background: ${summary.backgrounded}',
      'Verdict: ${summary.hadWorryingGap ? 'the phone paused the app' : 'kept sharing the whole way'}',
      for (final reason in summary.stops) 'Stopped: $reason',
    ]);
  }

  return lines.join('\n');
}
