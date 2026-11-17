import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../maps/data/polyline.dart';
import '../../maps/presentation/app_map.dart';
import '../application/family_learning_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_account.dart';
import '../data/models/family_bus.dart';
import 'family_more_screens.dart';
import 'widgets/family_widgets.dart';

/// The Bus tab (docs/parent-student-app.md, F4): the child's route, stop and
/// vehicle, today's trips as they went for the child, who to call, and -
/// while their own trip is on the road - a way to follow the bus.
class FamilyBusScreen extends ConsumerWidget {
  const FamilyBusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);
    if (child == null) {
      return const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show');
    }

    return ref
        .watch(familyBusProvider(child.id))
        .when(
          skipLoadingOnRefresh: true,
          loading: () => const PlaceholderCards(count: 3),
          error: (error, _) =>
              FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyBusProvider(child.id))),
          data: (bus) => RefreshIndicator(
            onRefresh: () => ref.read(familyBusProvider(child.id).notifier).refresh(),
            child: bus == null ? const _NotOnABus() : _BusList(child: child, bus: bus),
          ),
        );
  }
}

class _NotOnABus extends StatelessWidget {
  const _NotOnABus();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 60),
        FamilyEmptyView(
          icon: Icons.directions_bus_outlined,
          title: 'Not on a school bus',
          message: 'If your child should be, the school office can add them to a route.',
        ),
      ],
    );
  }
}

class _BusList extends StatelessWidget {
  const _BusList({required this.child, required this.bus});

  final FamilyChild child;
  final FamilyBus bus;

  @override
  Widget build(BuildContext context) {
    final live = bus.liveTrip;
    final pickup = bus.trips.where((trip) => trip.isPickup).lastOrNull;
    final drop = bus.trips.where((trip) => !trip.isPickup).lastOrNull;

    return ListView(
      key: const Key('family-bus'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (live != null) ...[_TrackTheBus(child: child, trip: live), const SizedBox(height: 12)],
        _RouteCard(bus: bus),
        const SizedBox(height: 12),
        _TripTimeline(title: 'To school', trip: pickup, stopName: bus.stop?.name, childName: child.firstName),
        const SizedBox(height: 12),
        _TripTimeline(title: 'Home', trip: drop, stopName: bus.stop?.name, childName: child.firstName),
        if (bus.officePhone != null || bus.attendant != null) ...[const SizedBox(height: 12), _Contacts(bus: bus)],
      ],
    );
  }
}

/// The way to the map, shown only while the child's trip is on the road.
class _TrackTheBus extends StatelessWidget {
  const _TrackTheBus({required this.child, required this.trip});

  final FamilyChild child;
  final FamilyBusTrip trip;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return FamilyCard(
      key: const Key('family-track-bus'),
      onTap: () => context.push('/bus/live'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: colours.successContainer, shape: BoxShape.circle),
            child: Icon(Icons.directions_bus_rounded, color: colours.onSuccessContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.isPickup ? 'The bus is on its way to school' : 'The bus is on its way home',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('Track it on the map', style: TextStyle(color: colours.muted, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.bus});

  final FamilyBus bus;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final stop = bus.stop;

    return FamilyCard(
      key: const Key('family-bus-route'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(icon: Icons.route_rounded, title: 'Route and stop'),
          const SizedBox(height: 12),
          Text(bus.routeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (stop != null) Text(stop.name, style: TextStyle(color: muted)),
          if (bus.vehicleName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [bus.vehicleName, bus.vehicleNumber].whereType<String>().join(' · '),
                key: const Key('family-bus-vehicle'),
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
          if (stop != null && (stop.pickupTime != null || stop.dropTime != null)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (stop.pickupTime != null)
                  Expanded(
                    child: _Time(label: 'Pick-up', time: stop.pickupTime!),
                  ),
                if (stop.dropTime != null)
                  Expanded(
                    child: _Time(label: 'Drop', time: stop.dropTime!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time({required this.label, required this.time});

  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.appColors.muted, fontSize: 12)),
        Text(formatClock(time), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// One of today's trips, as the moments that matter to this child.
class _TripTimeline extends StatelessWidget {
  const _TripTimeline({required this.title, required this.trip, required this.stopName, required this.childName});

  final String title;
  final FamilyBusTrip? trip;
  final String? stopName;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final trip = this.trip;
    final stop = stopName ?? 'your stop';

    final List<(String, String?)> steps;
    String? note;

    if (trip == null) {
      steps = const [];
      note = 'Not started yet';
    } else if (trip.isCancelled) {
      steps = const [];
      note = 'This trip was cancelled. The school will be in touch.';
    } else if (trip.riderStatus == null) {
      steps = const [];
      note = '$childName is not on this trip\'s list today.';
    } else if (trip.isPickup) {
      steps = [
        ('The bus set off', trip.startedAt),
        ('Reached $stop', trip.reachedStopAt),
        if (trip.riderStatus == 'absent') ('Did not board', null) else ('$childName boarded', trip.boardedAt),
        ('Reached school', trip.status == 'completed' ? trip.endedAt : null),
      ];
    } else {
      steps = [
        ('The bus left school', trip.startedAt),
        if (trip.riderStatus == 'absent') ('Did not board', null) else ('$childName boarded', trip.boardedAt),
        ('Reached $stop', trip.reachedStopAt),
        ('$childName got off', trip.droppedAt),
      ];
    }

    return FamilyCard(
      key: Key('family-trip-${title == 'Home' ? 'drop' : 'pickup'}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            icon: title == 'Home' ? Icons.home_rounded : Icons.school_rounded,
            title: title,
            colour: trip?.isLive == true ? colours.success : colours.info,
          ),
          const SizedBox(height: 10),
          if (note != null) Text(note, style: TextStyle(color: colours.muted)),
          for (final (index, (label, time)) in steps.indexed)
            _Step(label: label, time: time, absent: label == 'Did not board', last: index == steps.length - 1),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.time, required this.absent, required this.last});

  final String label;
  final String? time;
  final bool absent;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final done = time != null;
    final dot = absent ? colours.warning : (done ? colours.success : colours.muted.withValues(alpha: 0.4));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Icon(done || absent ? Icons.circle : Icons.circle_outlined, size: 12, color: dot),
                if (!last) Expanded(child: Container(width: 2, color: colours.muted.withValues(alpha: 0.2))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                        color: done || absent ? null : colours.muted,
                      ),
                    ),
                  ),
                  if (time != null) Text(formatClock(time!), style: TextStyle(color: colours.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Contacts extends ConsumerWidget {
  const _Contacts({required this.bus});

  final FamilyBus bus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget row(String label, String who, String number, Key key) => ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(who, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$label · $number'),
      trailing: IconButton(
        tooltip: 'Call',
        icon: const Icon(Icons.call_rounded),
        onPressed: () => ref.read(externalOpenerProvider)(Uri(scheme: 'tel', path: number.replaceAll(' ', ''))),
      ),
    );

    return FamilyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(icon: Icons.support_agent_rounded, title: 'Questions about the bus'),
          if (bus.attendant != null)
            row('Bus attendant', bus.attendant!.name, bus.attendant!.mobile, const Key('family-call-attendant')),
          if (bus.officePhone != null)
            row('Transport office', 'The school office', bus.officePhone!, const Key('family-call-transport')),
        ],
      ),
    );
  }
}

// -- Following the bus ----------------------------------------------------------------

/// How often the map asks where the bus is. The crew's phone reports about
/// as often, so asking faster shows nothing new.
const busRefreshInterval = Duration(seconds: 15);

/// The bus on a map during the child's own trip (decision D9), refreshed
/// every [busRefreshInterval]. When the trip stops being theirs - they got
/// off, or it ended - it says so instead of showing an old position.
class FamilyBusLiveScreen extends ConsumerStatefulWidget {
  const FamilyBusLiveScreen({super.key});

  @override
  ConsumerState<FamilyBusLiveScreen> createState() => _FamilyBusLiveScreenState();
}

class _FamilyBusLiveScreenState extends ConsumerState<FamilyBusLiveScreen> {
  Timer? _timer;
  FamilyBusLive? _live;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(busRefreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final child = ref.read(selectedChildProvider);
    if (child == null) return;

    try {
      final live = await ref.read(familyRepositoryProvider).busLive(child.id);
      if (!mounted) return;
      setState(() {
        _live = live;
        _loaded = true;
        _error = null;
      });
      if (live == null) _timer?.cancel();
    } on Failure catch (failure) {
      if (!mounted) return;
      // A refresh that fails keeps the last position on screen; only a
      // first load with nothing to show becomes the error view.
      setState(() {
        _error = failure;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final live = _live;

    final Widget body;
    if (!_loaded) {
      body = const PlaceholderCards(count: 2);
    } else if (live == null && _error != null) {
      body = FamilyErrorView(error: _error!, onRetry: _load);
    } else if (live == null) {
      body = FamilyEmptyView(
        icon: Icons.directions_bus_outlined,
        title: 'The bus isn\'t on the road for ${child?.firstName ?? 'your child'} now',
        message: 'You can follow it during their trip - on the way to school or home.',
      );
    } else {
      body = _LiveView(live: live, offline: _error != null);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Where is the bus?')),
      body: body,
    );
  }
}

class _LiveView extends StatelessWidget {
  const _LiveView({required this.live, required this.offline});

  final FamilyBusLive live;

  /// The last refresh failed; what is shown is from before it.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final position = live.position;
    final stop = live.yourStop;
    final stopPoint = stop?.location;
    final centre = position?.point ?? stopPoint;

    return Column(
      key: const Key('family-bus-live'),
      children: [
        Expanded(
          child: centre == null
              ? const SizedBox.shrink()
              : AppMap(
                  view: AppMapView(
                    centre: LatLng(centre.latitude, centre.longitude),
                    zoom: 14,
                    markers: {
                      if (position != null)
                        Marker(
                          markerId: const MarkerId('bus'),
                          position: LatLng(position.point.latitude, position.point.longitude),
                          rotation: position.heading ?? 0,
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                          infoWindow: const InfoWindow(title: 'The bus'),
                        ),
                      if (stopPoint != null)
                        Marker(
                          markerId: const MarkerId('your-stop'),
                          position: LatLng(stopPoint.latitude, stopPoint.longitude),
                          infoWindow: InfoWindow(title: stop!.name),
                        ),
                    },
                    polylines: {
                      if (decodePolyline(live.routePath).isNotEmpty)
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: decodePolyline(live.routePath),
                          width: 5,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                        ),
                    },
                  ),
                ),
        ),
        _WhereItIs(live: live, offline: offline),
      ],
    );
  }
}

/// The map in words, for a glance - and for a phone with no map.
class _WhereItIs extends StatelessWidget {
  const _WhereItIs({required this.live, required this.offline});

  final FamilyBusLive live;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final stop = live.yourStop;
    final position = live.position;

    final String headline;
    final List<String> details = [];

    if (stop == null) {
      headline = 'The bus is on the road';
    } else if (stop.reached) {
      headline = live.direction == 'pickup' ? 'The bus has been to ${stop.name}' : 'The bus has reached ${stop.name}';
    } else {
      headline = 'On its way to ${stop.name}';
      if (stop.etaSeconds != null) details.add('about ${_minutes(stop.etaSeconds!)}');
      if (stop.distanceM != null) details.add('${_distance(stop.distanceM!)} away');
      if (stop.stopsBefore != null && stop.stopsBefore! > 0) {
        details.add('${stop.stopsBefore} ${stop.stopsBefore == 1 ? 'stop' : 'stops'} before yours');
      }
    }

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(headline, key: const Key('family-bus-headline'), style: Theme.of(context).textTheme.titleMedium),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(details.join(' · '), style: TextStyle(color: colours.muted)),
            ],
            if (position == null)
              _Warning(text: 'Waiting for the bus to share where it is.', colour: colours.muted)
            else if (position.isStale)
              _Warning(
                text: 'Last seen ${_minutes(position.ageSeconds)} ago - the bus may be out of signal.',
                colour: colours.warning,
              ),
            if (offline) _Warning(text: 'No connection - showing the last update.', colour: colours.warning),
          ],
        ),
      ),
    );
  }

  static String _minutes(int seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes <= 1 ? '1 minute' : '$minutes minutes';
  }

  static String _distance(int metres) =>
      metres < 1000 ? '${(metres / 50).round() * 50} m' : '${(metres / 1000).toStringAsFixed(1)} km';
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colour),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: colour)),
          ),
        ],
      ),
    );
  }
}
