import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../data/models/transport_trip.dart';
import '../../../../core/utils/date_format.dart';
import 'trip_live_location_card.dart';

/// The prototype's live-tracking panel: trip header, KPIs, where the bus is
/// (a running trip only), the stop strip, "Students on Bus" and the
/// timeline. Read-only unless [onReachStop] / [onRiderStatus] are given (a
/// running trip seen by a managing role).
class TripDetailView extends StatelessWidget {
  const TripDetailView({super.key, required this.trip, this.onReachStop, this.onRiderStatus, this.busy = false});

  final TransportTrip trip;
  final ValueChanged<TripStop>? onReachStop;
  final void Function(TripRider rider, TripRiderStatus status)? onRiderStatus;

  /// While an action is in flight the buttons are disabled but stay in place,
  /// so the table does not jump around under the driver's finger.
  final bool busy;

  bool get _canManage => trip.isInProgress && onReachStop != null && onRiderStatus != null;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(trip.routeLabel, style: Theme.of(context).textTheme.titleMedium),
                    StatusBadge(label: trip.direction.label, tone: BadgeTone.neutral),
                    TripStatusBadge(status: trip.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Driver: ${trip.driverName}${trip.driverMobile == null ? '' : ' (${trip.driverMobile})'} · '
                  '${trip.vehicleName} ${trip.vehicleRegistrationNumber} · '
                  '${formatDate(DateTime.parse(trip.tripDate))}',
                  style: muted,
                ),
                if (trip.currentStopName != null) ...[
                  const SizedBox(height: 4),
                  Text('Last stop reached: ${trip.currentStopName}', style: muted),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    KpiCard(label: 'Students', value: '${trip.ridersCount}'),
                    KpiCard(label: 'Boarded', value: '${trip.boardedCount ?? 0}'),
                    KpiCard(label: 'Dropped', value: '${trip.droppedCount ?? 0}'),
                    KpiCard(label: 'Absent', value: '${trip.absentCount ?? 0}'),
                    KpiCard(
                      label: 'Stops Left',
                      value: '${trip.stopsLeft ?? trip.stops.where((s) => !s.reached).length}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Only while the trip runs: the card polls, and taking it off the
        // screen when the trip ends is what stops the polling.
        if (trip.isInProgress) ...[const SizedBox(height: 16), TripLiveLocationCard(tripId: trip.id)],
        const SizedBox(height: 16),
        Text('Stops', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (trip.stops.isEmpty)
          const Card(
            child: Padding(padding: EdgeInsets.all(16), child: Text('This route has no stops.')),
          )
        else
          Card(
            child: Column(
              children: [
                for (final stop in trip.stops)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      stop.reached ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: stop.reached ? context.appColors.success : null,
                    ),
                    title: Text('${stop.sequenceNumber}. ${stop.name}'),
                    subtitle: Text(
                      [
                        if (stop.pickupTime != null) 'Pickup ${stop.pickupTime}',
                        if (stop.dropTime != null) 'Drop ${stop.dropTime}',
                      ].join(' · '),
                    ),
                    trailing: _canManage && !stop.reached
                        ? OutlinedButton(
                            onPressed: busy ? null : () => onReachStop!(stop),
                            child: const Text('Reached'),
                          )
                        : (stop.id == trip.currentStopId
                              ? const StatusBadge(label: 'Current', tone: BadgeTone.info)
                              : null),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text('Students on Bus', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (trip.riders.isEmpty)
          const Card(
            child: Padding(padding: EdgeInsets.all(16), child: Text('No students were expected on this trip.')),
          )
        else
          ResponsiveBuilder(
            mobile: (context) => _RiderCards(trip: trip, onRiderStatus: _canManage ? onRiderStatus : null, busy: busy),
            desktop: (context) => _RiderTable(trip: trip, onRiderStatus: _canManage ? onRiderStatus : null, busy: busy),
          ),
        const SizedBox(height: 16),
        Text('Trip Timeline', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final event in trip.events)
                ListTile(
                  dense: true,
                  leading: Text(_time(event.recordedAtLabel), style: const TextStyle(fontWeight: FontWeight.w700)),
                  title: event.type == TripEventType.guardianCalled
                      ? Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(child: Text(event.description)),
                          ],
                        )
                      : Text(event.description),
                  subtitle: event.recordedByName == null ? null : Text('by ${event.recordedByName}', style: muted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The API renders event times in the school's timezone; see TripEvent.
  static String _time(String? label) => label ?? '-';
}

class TripStatusBadge extends StatelessWidget {
  const TripStatusBadge({super.key, required this.status});

  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      TripStatus.inProgress => BadgeTone.info,
      TripStatus.completed => BadgeTone.success,
      TripStatus.cancelled => BadgeTone.danger,
    };
    return StatusBadge(label: status.label, tone: tone);
  }
}

/// The prototype's Pickup / Drop columns: pickup = boarded yet, drop =
/// dropped yet.
class _PickupBadge extends StatelessWidget {
  const _PickupBadge({required this.rider});

  final TripRider rider;

  @override
  Widget build(BuildContext context) {
    return switch (rider.status) {
      TripRiderStatus.pending => const StatusBadge(label: 'Pending', tone: BadgeTone.warning),
      TripRiderStatus.absent => const StatusBadge(label: 'Absent', tone: BadgeTone.danger),
      TripRiderStatus.boarded ||
      TripRiderStatus.dropped => const StatusBadge(label: 'Boarded', tone: BadgeTone.success),
    };
  }
}

class _DropBadge extends StatelessWidget {
  const _DropBadge({required this.rider});

  final TripRider rider;

  @override
  Widget build(BuildContext context) {
    return switch (rider.status) {
      TripRiderStatus.dropped => const StatusBadge(label: 'Dropped', tone: BadgeTone.success),
      TripRiderStatus.absent => const StatusBadge(label: '—', tone: BadgeTone.neutral),
      _ => const StatusBadge(label: 'Pending', tone: BadgeTone.warning),
    };
  }
}

class _RiderActions extends StatelessWidget {
  const _RiderActions({required this.rider, required this.onRiderStatus, required this.busy});

  final TripRider rider;
  final void Function(TripRider rider, TripRiderStatus status) onRiderStatus;
  final bool busy;

  void Function()? _tap(TripRiderStatus status) {
    return busy ? null : () => onRiderStatus(rider, status);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rider.status == TripRiderStatus.pending) ...[
          FilledButton(onPressed: _tap(TripRiderStatus.boarded), child: const Text('Board')),
          const SizedBox(width: 6),
          TextButton(onPressed: _tap(TripRiderStatus.absent), child: const Text('Absent')),
        ],
        if (rider.status == TripRiderStatus.boarded)
          FilledButton(onPressed: _tap(TripRiderStatus.dropped), child: const Text('Drop')),
      ],
    );
  }
}

class _RiderTable extends StatelessWidget {
  const _RiderTable({required this.trip, required this.onRiderStatus, required this.busy});

  final TransportTrip trip;
  final void Function(TripRider rider, TripRiderStatus status)? onRiderStatus;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: HorizontalScrollTable(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Student')),
            const DataColumn(label: Text('Stop')),
            const DataColumn(label: Text('Pickup')),
            const DataColumn(label: Text('Drop')),
            if (onRiderStatus != null) const DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final rider in trip.riders)
              DataRow(
                cells: [
                  DataCell(Text('${rider.name} · ${rider.classSectionName ?? rider.admissionNumber}')),
                  DataCell(Text('${rider.stopSequenceNumber}. ${rider.stopName}')),
                  DataCell(_PickupBadge(rider: rider)),
                  DataCell(_DropBadge(rider: rider)),
                  if (onRiderStatus != null)
                    DataCell(_RiderActions(rider: rider, onRiderStatus: onRiderStatus!, busy: busy)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RiderCards extends StatelessWidget {
  const _RiderCards({required this.trip, required this.onRiderStatus, required this.busy});

  final TransportTrip trip;
  final void Function(TripRider rider, TripRiderStatus status)? onRiderStatus;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    // Full width so the cards line up instead of shrink-wrapping to their text.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rider in trip.riders)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rider.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${rider.stopSequenceNumber}. ${rider.stopName} · ${rider.classSectionName ?? rider.admissionNumber}',
                    style: muted,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _PickupBadge(rider: rider),
                      _DropBadge(rider: rider),
                      if (onRiderStatus != null) _RiderActions(rider: rider, onRiderStatus: onRiderStatus!, busy: busy),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
