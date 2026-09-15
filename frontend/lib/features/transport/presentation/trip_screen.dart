import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/live_trip_notifier.dart';
import '../application/transport_pickers.dart';
import '../application/trip_history_notifier.dart';
import '../data/models/transport_route.dart';
import '../data/models/transport_trip.dart';
import 'widgets/trip_detail_view.dart';
import '../../../core/utils/date_format.dart';

/// Who runs trips - the prototype's "Manage Trips" (Transport Manager)
/// plus the admins.
const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.transportManager};

/// Phase 15 - the prototype's "School Transport" page: pick a route, start
/// today's pickup/drop trip, mark stops reached and students boarded /
/// dropped / absent, end it - plus the history of past trips.
class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key});

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  int? _schoolId;
  int? _routeId;

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final canManage = _manageRoles.contains(actor.role);
    final needsSchool = actor.role == UserRole.superAdmin && _schoolId == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('School Transport', style: Theme.of(context).textTheme.headlineSmall),
              SchoolFilterDropdown(
                selected: _schoolId,
                onChanged: (schoolId) {
                  setState(() {
                    _schoolId = schoolId;
                    _routeId = null;
                  });
                  ref.read(tripHistoryNotifierProvider.notifier).setFilters(schoolId: schoolId, routeId: null);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Live bus operations and student trip events.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (needsSchool)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Pick a school to run its trips.')),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 320,
                  child: _RoutePicker(
                    schoolId: _schoolId,
                    selected: _routeId,
                    onChanged: (value) {
                      setState(() => _routeId = value);
                      ref.read(tripHistoryNotifierProvider.notifier).setFilters(schoolId: _schoolId, routeId: value);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_routeId == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Pick a route to see its trip for today.')),
                ),
              )
            else
              _LiveTripPanel(
                key: ValueKey('live-$_schoolId-$_routeId'),
                params: LiveTripParams(schoolId: _schoolId, routeId: _routeId!),
                canManage: canManage,
              ),
            const SizedBox(height: 24),
            Text('Trip History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const _TripHistory(),
          ],
        ],
      ),
    );
  }
}

class _RoutePicker extends ConsumerWidget {
  const _RoutePicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesState = ref.watch(routePickerProvider(schoolId));
    final routes = routesState.value ?? const <TransportRoute>[];

    return DropdownButtonFormField<int>(
      key: ValueKey('trip-route-${routes.length}'),
      initialValue: routes.any((r) => r.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Route',
        helperText: routesState.isLoading
            ? 'Loading routes…'
            : (routesState.hasValue && routes.isEmpty ? 'No active routes yet - set one up under Routes.' : null),
      ),
      items: [for (final route in routes) DropdownMenuItem(value: route.id, child: Text(route.label))],
      onChanged: routesState.isLoading ? null : onChanged,
    );
  }
}

class _LiveTripPanel extends ConsumerStatefulWidget {
  const _LiveTripPanel({super.key, required this.params, required this.canManage});

  final LiveTripParams params;
  final bool canManage;

  @override
  ConsumerState<_LiveTripPanel> createState() => _LiveTripPanelState();
}

class _LiveTripPanelState extends ConsumerState<_LiveTripPanel> {
  TripDirection? _chosenDirection;
  bool _busy = false;

  /// Morning at the school is a pickup run. The browser could be in another
  /// country entirely, so its hour means nothing here. Resolved on build
  /// rather than in initState, since the session carrying the school's clock
  /// may still be loading when this panel first mounts.
  TripDirection get _direction =>
      _chosenDirection ?? (ref.read(schoolClockProvider).now.hour < 12 ? TripDirection.pickup : TripDirection.drop);

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Boarding a bus-load of students fires many quick actions; each result
    // replaces the previous snackbar instead of queueing behind it.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (successMessage != null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on _Aborted {
      // The confirm dialog was dismissed - nothing happened.
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm({required String title, required String message, required String action}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    if (ok != true) throw _Aborted();
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(liveTripProvider(widget.params));
    final notifier = ref.read(liveTripProvider(widget.params).notifier);

    return AsyncValueView<TransportTrip?>(
      value: tripState,
      onRetry: notifier.refresh,
      data: (context, trip) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trip == null || !trip.isInProgress) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        trip == null
                            ? 'No trip in progress for this route.'
                            : 'Last trip ${trip.status.label.toLowerCase()}.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (widget.canManage) ...[
                        SegmentedButton<TripDirection>(
                          segments: [
                            for (final d in TripDirection.values) ButtonSegment(value: d, label: Text(d.label)),
                          ],
                          selected: {_direction},
                          onSelectionChanged: (s) => setState(() => _chosenDirection = s.first),
                        ),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => notifier.start(_direction),
                                  successMessage: '${_direction.label} trip started.',
                                ),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Start Trip'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (trip != null) ...[const SizedBox(height: 16), TripDetailView(trip: trip)],
            ] else ...[
              if (widget.canManage)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await _confirm(
                                  title: 'End trip?',
                                  message: 'Students who never boarded will be marked absent. Anyone still on board must be dropped first.',
                                  action: 'End Trip',
                                );
                                await notifier.end();
                              }, successMessage: 'Trip completed.'),
                        icon: const Icon(Icons.flag, size: 18),
                        label: const Text('End Trip'),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await _confirm(
                                  title: 'Cancel trip?',
                                  message: 'The trip will be marked cancelled and can be started again today.',
                                  action: 'Cancel Trip',
                                );
                                await notifier.cancel();
                              }, successMessage: 'Trip cancelled.'),
                        child: const Text('Cancel Trip'),
                      ),
                    ],
                  ),
                ),
              TripDetailView(
                trip: trip,
                busy: _busy,
                onReachStop: widget.canManage
                    ? (stop) => _run(() => notifier.reachStop(stop.id), successMessage: 'Reached ${stop.name}.')
                    : null,
                onRiderStatus: widget.canManage
                    ? (rider, status) => _run(
                        () => notifier.updateRider(rider.studentId, status),
                        successMessage: '${rider.name} ${status.label.toLowerCase()}.',
                      )
                    : null,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Thrown to unwind `_run` when the confirm dialog is dismissed.
class _Aborted implements Exception {}

class _TripHistory extends ConsumerWidget {
  const _TripHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(tripHistoryNotifierProvider);

    return AsyncValueView<PagedList<TransportTrip>>(
      value: historyState,
      onRetry: () => ref.read(tripHistoryNotifierProvider.notifier).refresh(),
      isEmpty: (page) => page.items.isEmpty,
      emptyBuilder: (context) => const Card(
        child: Padding(padding: EdgeInsets.all(20), child: Text('No trips have been run yet.')),
      ),
      data: (context, page) {
        return Column(
          children: [
            ResponsiveBuilder(
              mobile: (context) => _HistoryCards(trips: page.items),
              desktop: (context) => _HistoryTable(trips: page.items),
            ),
            PaginationControls(
              currentPage: page.currentPage,
              lastPage: page.lastPage,
              total: page.total,
              perPage: page.perPage,
              onPageChanged: (p) => ref.read(tripHistoryNotifierProvider.notifier).goToPage(p),
              onPerPageChanged: (p) => ref.read(tripHistoryNotifierProvider.notifier).setPerPage(p),
            ),
          ],
        );
      },
    );
  }
}

/// The API renders trip times in the school's timezone, because the browser
/// has no timezone database and could be in another country entirely.
String _when(String? label) => label ?? '-';

String _historyRange(TransportTrip trip) =>
    '${_when(trip.startedAtLabel)}${trip.endedAtLabel == null ? '' : ' – ${_when(trip.endedAtLabel)}'}';

void _openDetail(BuildContext context, TransportTrip trip) {
  showDialog(
    context: context,
    builder: (_) => TripHistoryDialog(tripId: trip.id),
  );
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.trips});

  final List<TransportTrip> trips;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: HorizontalScrollTable(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Route')),
            DataColumn(label: Text('Direction')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Students')),
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Action')),
          ],
          rows: [
            for (final trip in trips)
              DataRow(
                cells: [
                  DataCell(Text(formatDate(DateTime.parse(trip.tripDate)))),
                  DataCell(Text(trip.routeLabel)),
                  DataCell(Text(trip.direction.label)),
                  DataCell(TripStatusBadge(status: trip.status)),
                  DataCell(Text('${trip.ridersCount}')),
                  DataCell(Text(_historyRange(trip))),
                  DataCell(TextButton(onPressed: () => _openDetail(context, trip), child: const Text('View'))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCards extends StatelessWidget {
  const _HistoryCards({required this.trips});

  final List<TransportTrip> trips;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      children: [
        for (final trip in trips)
          Card(
            child: ListTile(
              title: Text('${trip.routeLabel} · ${trip.direction.label}'),
              subtitle: Text(
                '${formatDate(DateTime.parse(trip.tripDate))} · ${_historyRange(trip)} · ${trip.ridersCount} students',
                style: muted,
              ),
              trailing: TripStatusBadge(status: trip.status),
              onTap: () => _openDetail(context, trip),
            ),
          ),
      ],
    );
  }
}

/// A past trip, read-only.
class TripHistoryDialog extends ConsumerWidget {
  const TripHistoryDialog({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripDetailProvider(tripId));

    return AlertDialog(
      title: const Text('Trip details'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 640, maxWidth: 640, maxHeight: 560),
        child: SingleChildScrollView(
          child: AsyncValueView<TransportTrip>(
            value: tripState,
            onRetry: () => ref.invalidate(tripDetailProvider(tripId)),
            data: (context, trip) => TripDetailView(trip: trip),
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}
