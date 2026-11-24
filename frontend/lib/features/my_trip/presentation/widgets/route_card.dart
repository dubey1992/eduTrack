import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/offline_start.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../transport/data/models/transport_trip.dart';
import '../../application/my_routes_notifier.dart';
import '../../application/trip_mark_queue.dart';
import '../../data/apply_marks.dart';
import '../../data/models/my_route.dart';
import '../../data/my_trip_repository.dart';
import '../trip_words.dart';

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
      if (isLocalTrip(trip.id) && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(key: const Key('trip-started-on-phone'), content: Text(context.l10n.busStartedOnPhone)),
          );
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      // Only when this phone has never seen the route's children - a trip
      // needs them, and they come with My routes.
      final message = failure.isOffline ? context.l10n.busRouteNotSaved : failure.localizedMessage(context);
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
    final l10n = context.l10n;

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
                if (route.driverName != null) l10n.busDriverName(route.driverName!),
              ].join(' · '),
              style: TextStyle(color: muted),
            ),
            Text(
              '${l10n.busStopsCount(route.stopsCount)} · ${l10n.busStudentsCount(route.studentsCount)}',
              style: TextStyle(color: muted),
            ),
            if (route.myLicenceExpiry != null) ...[
              const SizedBox(height: 12),
              _LicenceWarning(expiry: route.myLicenceExpiry!),
            ],
            const SizedBox(height: 16),
            for (final direction in TripDirection.values) ...[
              _TripTile(
                direction: direction,
                trip: shown(direction),
                starting: _starting == direction,
                // A drop takes home the children a pickup brought in, so it
                // waits for the morning run. The server refuses it too; this
                // only keeps the crew from meeting that refusal
                // (docs/driver-app.md).
                waitingForPickup: direction == TripDirection.drop && route.tripFor(TripDirection.pickup) == null,
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

/// The driver's own licence, when it is close enough to matter.
///
/// Shown on the duty screen rather than left to the office, because the
/// driver is the only person who can renew it and the office finds out on
/// the morning the bus cannot legally run (docs/driver-app.md, D3.4). It
/// never blocks a trip: a lapsed licence is a conversation with the school,
/// not a reason to strand children at a stop.
class _LicenceWarning extends StatelessWidget {
  const _LicenceWarning({required this.expiry});

  /// How long before it runs out the driver starts being told.
  static const notice = Duration(days: 30);

  final DateTime expiry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final today = DateTime.now();
    final days = DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;

    if (days > notice.inDays) return const SizedBox.shrink();

    final lapsed = days < 0;
    final l10n = context.l10n;
    final message = switch (days) {
      < 0 => l10n.busLicenceExpired(formatDate(expiry)),
      0 => l10n.busLicenceToday,
      1 => l10n.busLicenceTomorrow,
      _ => l10n.busLicenceInDays(days, formatDate(expiry)),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: lapsed ? colors.dangerContainer : colors.warningContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            lapsed ? Icons.error_outline : Icons.warning_amber_outlined,
            size: 20,
            color: lapsed ? colors.onDangerContainer : colors.onWarningContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: lapsed ? colors.onDangerContainer : colors.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({
    required this.direction,
    required this.trip,
    required this.starting,
    required this.waitingForPickup,
    required this.onStart,
    required this.onOpen,
  });

  final TripDirection direction;
  final TransportTrip? trip;
  final bool starting;

  /// The day's pickup has not been started, so this drop cannot be.
  final bool waitingForPickup;
  final VoidCallback? onStart;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final trip = this.trip;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final (badge, tone) = switch (trip?.status) {
      null => (l10n.busNotStarted, BadgeTone.neutral),
      TripStatus.inProgress => (l10n.busEnRoute, BadgeTone.info),
      TripStatus.completed => (l10n.busCompleted, BadgeTone.success),
      TripStatus.cancelled => (l10n.busCancelled, BadgeTone.danger),
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
                child: Text(direction.labelIn(l10n), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              StatusBadge(label: badge, tone: tone),
            ],
          ),
          if (trip != null && trip.status != TripStatus.inProgress) ...[
            const SizedBox(height: 6),
            Text(_summary(l10n, trip), style: TextStyle(color: context.appColors.muted)),
          ],
          // Why the button is grey, where it is. A disabled control with no
          // reason beside it reads as a broken app.
          if (trip == null && waitingForPickup) ...[
            const SizedBox(height: 6),
            Text(l10n.busDropWaits, style: TextStyle(color: context.appColors.muted)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: switch (trip?.status) {
              null => FilledButton.icon(
                key: Key('start-${direction.apiValue}'),
                onPressed: waitingForPickup ? null : onStart,
                icon: starting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(direction.startIn(l10n)),
              ),
              TripStatus.inProgress => FilledButton.icon(
                key: Key('continue-${direction.apiValue}'),
                onPressed: () => onOpen(trip!.id),
                icon: const Icon(Icons.directions_bus_filled),
                label: Text(direction.continueIn(l10n)),
              ),
              _ => OutlinedButton(
                key: Key('view-${direction.apiValue}'),
                onPressed: () => onOpen(trip!.id),
                child: Text(l10n.busViewTrip),
              ),
            },
          ),
        ],
      ),
    );
  }

  String _summary(AppLocalizations l10n, TransportTrip trip) {
    final ended = trip.endedAtLabel;
    final riders = l10n.busStudentsCount(trip.ridersCount);
    return ended == null ? riders : l10n.busEndedAt(riders, ended);
  }
}
