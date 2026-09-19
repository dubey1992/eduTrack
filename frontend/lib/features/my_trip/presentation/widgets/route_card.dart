import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../transport/data/models/transport_trip.dart';
import '../../application/my_routes_notifier.dart';
import '../../application/trip_mark_queue.dart';
import '../../data/apply_marks.dart';
import '../../data/models/my_route.dart';
import '../../data/my_trip_repository.dart';

/// One of the attendant's routes, with a card for today's pickup and one for
/// today's drop: Start, Continue, or how it went.
class RouteCard extends ConsumerStatefulWidget {
  const RouteCard({super.key, required this.route, required this.onOpenTrip});

  final MyRoute route;
  final ValueChanged<int> onOpenTrip;

  @override
  ConsumerState<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends ConsumerState<RouteCard> {
  /// The trip being started, so the button spins and a second tap is ignored.
  TripDirection? _starting;

  Future<void> _start(TripDirection direction) async {
    if (_starting != null) return;
    setState(() => _starting = direction);

    try {
      final trip = await ref.read(myRoutesProvider.notifier).start(routeId: widget.route.id, direction: direction);
      widget.onOpenTrip(trip.id);
    } on Failure catch (failure) {
      if (!mounted) return;
      final message = failure.isOffline
          ? 'Starting a trip needs a connection. Try again when you have signal.'
          : failure.message;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final queue = ref.watch(tripMarkQueueProvider);
    final muted = context.appColors.muted;

    // Today's trips as the attendant left them - an "End trip" still waiting
    // for signal already shows the trip as completed.
    TransportTrip? shown(TripDirection direction) {
      final trip = route.tripFor(direction);
      return trip == null ? null : applyMarks(trip, queue.marksFor(trip.id));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(route.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                if (route.vehicleName != null) route.vehicleName!,
                if (route.vehicleRegistrationNumber != null) route.vehicleRegistrationNumber!,
                if (route.driverName != null) 'Driver: ${route.driverName}',
              ].join(' · '),
              style: TextStyle(color: muted),
            ),
            Text('${route.stopsCount} stops · ${route.studentsCount} students', style: TextStyle(color: muted)),
            const SizedBox(height: 16),
            for (final direction in TripDirection.values) ...[
              _TripTile(
                direction: direction,
                trip: shown(direction),
                starting: _starting == direction,
                onStart: _starting == null ? () => _start(direction) : null,
                onOpen: widget.onOpenTrip,
              ),
              if (direction != TripDirection.values.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({
    required this.direction,
    required this.trip,
    required this.starting,
    required this.onStart,
    required this.onOpen,
  });

  final TripDirection direction;
  final TransportTrip? trip;
  final bool starting;
  final VoidCallback? onStart;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final trip = this.trip;
    final colorScheme = Theme.of(context).colorScheme;

    final (badge, tone) = switch (trip?.status) {
      null => ('Not started', BadgeTone.neutral),
      TripStatus.inProgress => ('En route', BadgeTone.info),
      TripStatus.completed => ('Completed', BadgeTone.success),
      TripStatus.cancelled => ('Cancelled', BadgeTone.danger),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(direction.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              StatusBadge(label: badge, tone: tone),
            ],
          ),
          if (trip != null && trip.status != TripStatus.inProgress) ...[
            const SizedBox(height: 6),
            Text(_summary(trip), style: TextStyle(color: context.appColors.muted)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: switch (trip?.status) {
              null => FilledButton.icon(
                key: Key('start-${direction.apiValue}'),
                onPressed: onStart,
                icon: starting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text('Start ${direction.label.toLowerCase()}'),
              ),
              TripStatus.inProgress => FilledButton.icon(
                key: Key('continue-${direction.apiValue}'),
                onPressed: () => onOpen(trip!.id),
                icon: const Icon(Icons.directions_bus_filled),
                label: Text('Continue ${direction.label.toLowerCase()}'),
              ),
              _ => OutlinedButton(
                key: Key('view-${direction.apiValue}'),
                onPressed: () => onOpen(trip!.id),
                child: const Text('View trip'),
              ),
            },
          ),
        ],
      ),
    );
  }

  String _summary(TransportTrip trip) {
    final ended = trip.endedAtLabel;
    final riders = '${trip.ridersCount} ${trip.ridersCount == 1 ? 'student' : 'students'}';
    return ended == null ? riders : '$riders · ended $ended';
  }
}
