import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/trip_live_location_notifier.dart';
import '../../data/models/trip_live_location.dart';

/// "Last seen 2 min ago" - how old the bus's last position was when the
/// server answered.
String lastSeenLabel(int ageSeconds) {
  if (ageSeconds < 60) return 'Last seen less than a minute ago';

  final minutes = ageSeconds ~/ 60;
  if (minutes < 60) return 'Last seen $minutes min ago';

  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'Last seen $hours h ago' : 'Last seen $hours h $rest min ago';
}

/// A Google Maps search link for a position - opens the maps app on a phone
/// and maps in a new tab in a browser, with no API key needed.
Uri mapsLink(String latitude, String longitude) {
  return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$latitude,$longitude'});
}

/// "about 1.2 km" / "about 350 m".
String distanceLabel(double metres) {
  final nearestTen = (metres / 10).round() * 10;
  if (nearestTen < 1000) return 'about $nearestTen m';
  return 'about ${(metres / 1000).toStringAsFixed(1)} km';
}

/// Where a running trip's bus is, refreshed every 15 seconds while this card
/// is on screen. There is no map yet - that comes with the map provider's
/// keys (docs/maps.md) - so the position is given as coordinates.
class TripLiveLocationCard extends ConsumerWidget {
  const TripLiveLocationCard({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveState = ref.watch(tripLiveLocationProvider(tripId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_bus_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Bus location', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            // Once there is an answer, a later refresh keeps showing it
            // rather than blinking to a spinner every 15 seconds.
            switch (liveState) {
              AsyncData(:final value) => _LiveDetails(live: value),
              AsyncError(:final error) => _LiveError(
                failure: error is Failure ? error : Failure.unknown(error.toString()),
                onRetry: () => ref.read(tripLiveLocationProvider(tripId).notifier).refresh(),
              ),
              _ => const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            },
          ],
        ),
      ),
    );
  }
}

class _LiveDetails extends StatelessWidget {
  const _LiveDetails({required this.live});

  final TripLiveLocation live;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final position = live.position;
    final nextStop = live.nextStop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (position == null)
          Text('No location shared yet.', style: muted)
        else ...[
          Text(
            position.isStale ? '${lastSeenLabel(position.ageSeconds)} (stale)' : lastSeenLabel(position.ageSeconds),
            style: position.isStale ? muted : const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText('${position.latitude}, ${position.longitude}', style: position.isStale ? muted : null),
              TextButton.icon(
                onPressed: () => _openInMaps(context, position),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Open in maps'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '${position.latitude},${position.longitude}'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordinates copied.')));
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(_nextStopLine(nextStop)),
      ],
    );
  }

  static Future<void> _openInMaps(BuildContext context, BusPosition position) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(mapsLink(position.latitude, position.longitude), mode: LaunchMode.externalApplication);
    } on PlatformException catch (error) {
      debugPrint('Could not open maps: ${error.message}');
    }
    if (!opened) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not open maps. Copy the coordinates instead.')));
    }
  }

  static String _nextStopLine(NextStop? stop) {
    if (stop == null) return 'Every stop has been reached.';

    final distance = stop.straightLineDistanceM;
    if (distance == null) return 'Next stop: ${stop.name}';

    return 'Next stop: ${stop.name} - ${distanceLabel(distance)} away (straight line)';
  }
}

class _LiveError extends StatelessWidget {
  const _LiveError({required this.failure, required this.onRetry});

  final Failure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(failure.message, style: TextStyle(color: context.appColors.danger)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
