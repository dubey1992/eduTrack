import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../transport/data/models/transport_trip.dart';
import '../../application/trip_detail_notifier.dart';
import '../../application/trip_mark_queue.dart';
import '../../data/models/not_sent_mark.dart';
import 'location_sharing_tile.dart';
import 'not_sent_card.dart';
import 'rider_tile.dart';

/// One trip, stop by stop, with each stop's children under it.
///
/// Every tap is a mark: it shows at once and waits on the phone until it
/// reaches the server (see TripMarkQueue), so nothing here waits on signal.
class RunningTripView extends ConsumerStatefulWidget {
  const RunningTripView({super.key, required this.tripId, required this.onBack});

  final int tripId;
  final VoidCallback onBack;

  @override
  ConsumerState<RunningTripView> createState() => _RunningTripViewState();
}

class _RunningTripViewState extends ConsumerState<RunningTripView> {
  /// A second tap this soon after the last is taken as the same tap - on a
  /// moving bus a double tap is easy, and the next button may sit under it.
  static const _tapGap = Duration(milliseconds: 400);

  /// Running while taps are being ignored.
  Timer? _tapCooldown;

  TripDetailNotifier get _trip => ref.read(tripDetailProvider(widget.tripId).notifier);

  bool _acceptTap() {
    if (_tapCooldown?.isActive ?? false) return false;
    _tapCooldown = Timer(_tapGap, () {});
    return true;
  }

  @override
  void dispose() {
    _tapCooldown?.cancel();
    super.dispose();
  }

  Future<void> _callParent(TripRider rider) async {
    final opened = await _trip.callParent(rider);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text("Could not open the phone's dialler.")));
    }
  }

  Future<void> _end(TransportTrip trip) async {
    final waiting = trip.riders.where((r) => r.status == TripRiderStatus.pending).length;
    final confirmed = await confirmDialog(
      context,
      title: 'End this trip?',
      message: waiting == 0
          ? 'Every child has been marked. The trip will be recorded as completed.'
          : '$waiting ${waiting == 1 ? 'child has' : 'children have'} not been marked and will be recorded as absent.',
      confirmLabel: 'End trip',
      cancelLabel: 'Keep going',
    );
    if (!confirmed || !mounted) return;

    await _trip.end();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Trip ended.')));
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(myTripViewProvider(widget.tripId));
    final notSent = ref.watch(tripMarkQueueProvider.select((queue) => queue.notSentFor(widget.tripId)));

    return AsyncValueView<TripSnapshot>(
      value: view,
      onRetry: () => ref.read(tripDetailProvider(widget.tripId).notifier).refresh(),
      data: (context, snapshot) => _buildTrip(context, snapshot, notSent),
    );
  }

  Widget _buildTrip(BuildContext context, TripSnapshot snapshot, List<NotSentMark> notSent) {
    final trip = snapshot.trip;
    final running = trip.isInProgress;
    final stops = [...trip.stops]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final nextStop = running ? stops.where((s) => !s.reached).firstOrNull : null;
    final stopIds = {for (final s in stops) s.id};
    final unplaced = trip.riders.where((r) => !stopIds.contains(r.stopId)).toList();
    final aboard = trip.riders.where((r) => r.status == TripRiderStatus.boarded).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('My routes'),
          ),
        ),
        _TripHeader(trip: trip),
        if (snapshot.fromCache)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'No signal - showing the trip as last saved on this phone.',
              style: TextStyle(color: context.appColors.muted, fontStyle: FontStyle.italic),
            ),
          ),
        if (running) LocationSharingTile(tripId: trip.id),
        if (notSent.isNotEmpty)
          NotSentCard(
            marks: notSent,
            onDismiss: (mark) => ref.read(tripMarkQueueProvider.notifier).dismissNotSent(mark.clientId),
          ),
        for (final stop in stops) ...[
          _StopHeader(
            stop: stop,
            direction: trip.direction,
            isNext: stop.id == nextStop?.id,
            onReached: () {
              if (_acceptTap()) _trip.reachStop(stop);
            },
          ),
          for (final rider in trip.riders.where((r) => r.stopId == stop.id)) _riderTile(rider, running),
        ],
        if (unplaced.isNotEmpty) ...[
          const _SectionTitle('Other riders'),
          for (final rider in unplaced) _riderTile(rider, running),
        ],
        const SizedBox(height: 16),
        if (running) ...[
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              key: const Key('end-trip'),
              onPressed: aboard > 0 ? null : () => _end(trip),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.flag),
              label: const Text('End trip'),
            ),
          ),
          if (aboard > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$aboard ${aboard == 1 ? 'child is' : 'children are'} still on board. Drop them off before ending the trip.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.muted),
              ),
            ),
        ],
      ],
    );
  }

  Widget _riderTile(TripRider rider, bool running) {
    return RiderTile(
      rider: rider,
      running: running,
      onMark: (status) {
        if (_acceptTap()) _trip.markRider(rider, status);
      },
      onCallParent: () {
        if (_acceptTap()) _callParent(rider);
      },
    );
  }
}

class _TripHeader extends StatelessWidget {
  const _TripHeader({required this.trip});

  final TransportTrip trip;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final (badge, tone) = switch (trip.status) {
      TripStatus.inProgress => ('En route', BadgeTone.info),
      TripStatus.completed => ('Completed', BadgeTone.success),
      TripStatus.cancelled => ('Cancelled', BadgeTone.danger),
    };
    int count(TripRiderStatus status) => trip.riders.where((r) => r.status == status).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.routeName} - ${trip.direction.label}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusBadge(label: badge, tone: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text('${trip.vehicleName} · ${trip.vehicleRegistrationNumber}', style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            Text(
              '${count(TripRiderStatus.boarded)} on board · ${count(TripRiderStatus.pending)} waiting · '
              '${count(TripRiderStatus.dropped)} dropped · ${count(TripRiderStatus.absent)} absent',
              key: const Key('trip-counts'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopHeader extends StatelessWidget {
  const _StopHeader({required this.stop, required this.direction, required this.isNext, required this.onReached});

  final TripStop stop;
  final TripDirection direction;
  final bool isNext;
  final VoidCallback onReached;

  @override
  Widget build(BuildContext context) {
    final time = direction == TripDirection.pickup ? stop.pickupTime : stop.dropTime;

    return Padding(
      key: Key('stop-${stop.id}'),
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Icon(
            stop.reached ? Icons.check_circle : Icons.location_on_outlined,
            color: stop.reached ? context.appColors.success : context.appColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${stop.sequenceNumber}. ${stop.name}${time == null ? '' : ' · $time'}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (stop.reached)
            const StatusBadge(label: 'Reached', tone: BadgeTone.success)
          else if (isNext)
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: Key('reach-stop-${stop.id}'),
                onPressed: onReached,
                icon: const Icon(Icons.place),
                label: const Text('Reached'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    );
  }
}
