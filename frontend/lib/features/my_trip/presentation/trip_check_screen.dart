import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Trip check')),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(child: Text('The trip log could not be read.')),
        data: (list) {
          final summary = TripHealthSummary.of(list);
          final exempt = mayStop.value == null ? null : !mayStop.value!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PhoneCard(exempt: exempt),
              const SizedBox(height: 12),
              if (summary == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No trip has shared its location on this phone yet. Run a trip with "Share my location" on, '
                      'then come back here.',
                    ),
                  ),
                )
              else
                _SummaryCard(summary: summary),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('trip-check-share'),
                onPressed: () => ref.read(shareTextProvider)(reportText(summary, exempt: exempt, at: DateTime.now())),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share report'),
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
                child: const Text('Clear the log'),
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

    return Card(
      child: ListTile(
        key: const Key('trip-check-battery'),
        leading: Icon(
          exempt == true ? Icons.battery_full : Icons.battery_alert,
          color: exempt == true ? colours.success : colours.warning,
        ),
        title: Text(switch (exempt) {
          true => 'Battery saving will not stop this app',
          false => 'Battery saving may stop this app',
          null => 'Checking battery settings...',
        }),
        subtitle: const Text("Some phones have their own setting as well - see the phone's battery steps."),
        trailing: TextButton(onPressed: () => context.push('/battery'), child: const Text('Steps')),
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
            Text('Last trip', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${DateFormat('MMM d').format(summary.from)}, ${time.format(summary.from)} - ${time.format(summary.to)}',
              style: TextStyle(color: colours.muted),
            ),
            const SizedBox(height: 8),
            row('Positions taken', '${summary.points}'),
            row(
              'Longest gap between positions',
              _minutes(summary.longestGap),
              colour: gapColour,
              key: const Key('trip-check-gap'),
            ),
            row('Sent to the school', '${summary.sent}'),
            row('Still waiting on this phone', '${summary.stillWaiting}'),
            if (summary.refused > 0) row('Refused by the server', '${summary.refused}', colour: colours.danger),
            if (summary.cleared > 0) row('Dropped after the trip ended', '${summary.cleared}', colour: colours.warning),
            row('Times the app went to the background', '${summary.backgrounded}'),
            const SizedBox(height: 8),
            Text(
              summary.hadWorryingGap
                  ? 'A gap of ${_minutes(summary.longestGap)} from ${time.format(summary.longestGapAt!)}: the phone '
                        'most likely paused the app. Follow the battery steps for this phone and run a trip again.'
                  : 'No long gaps: the phone kept sharing the whole way.',
              key: const Key('trip-check-verdict'),
              style: TextStyle(color: gapColour, fontWeight: FontWeight.w600),
            ),
            for (final reason in summary.stops) ...[
              const SizedBox(height: 4),
              Text('Sharing stopped: $reason', style: TextStyle(color: colours.muted, fontSize: 12)),
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
