import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../maps/data/polyline.dart';
import '../../../maps/data/road_glide.dart';
import '../../../maps/presentation/app_map.dart';
import '../../../maps/presentation/fit_bounds.dart';
import '../../../maps/presentation/map_pin_icons.dart';
import '../../data/models/transport_route.dart';
import '../../application/trip_live_location_notifier.dart';
import '../../data/models/transport_trip.dart';
import '../../data/models/trip_live_location.dart';
import 'trip_live_location_card.dart';

/// Where a trip goes, and how far along it is (docs/maps.md, M3).
///
/// The road the route follows, the school at the end of it, and the stops
/// coloured by what the trip has done with them: reached, heading there
/// next, still to come. **None of this needs the bus to be sharing its
/// position** - it is drawn from the stop marks the trip already records,
/// so a trip that finished last week reads the same way as one running now.
class TripMap extends ConsumerWidget {
  const TripMap({super.key, required this.trip, this.bus, this.busAt, this.etaSeconds, this.height = 320});

  final TransportTrip trip;

  /// Where the bus was when the server last answered, or null - nobody has
  /// shared a position, the trip is not running, or the request is still in
  /// flight. The map is drawn either way; the bus is the one thing on it
  /// that is allowed to be missing.
  final BusPosition? bus;

  /// Where to draw the bus pin right now, when that is not [bus] itself:
  /// the pin glides along the road between two positions rather than
  /// jumping (see [TripMapCard]). Null draws it at [bus].
  final LatLng? busAt;

  /// How long until the bus reaches the next stop, when the server could
  /// work it out. Shown on the next stop's own pin rather than beside the
  /// bus: it is a fact about the stop somebody is waiting at.
  final int? etaSeconds;

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(mapPinIconsProvider).value;
    final placed = [
      for (final stop in trip.stops)
        if (_pointOf(stop) != null) stop,
    ];
    final school = _schoolPoint();
    final next = nextStop(trip);
    final busAt = _busPoint();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppMap(
          height: height,
          view: AppMapView(
            centre: _centre(placed, school),
            zoom: placed.isEmpty && school == null ? 4 : 12,
            markers: {
              if (school != null)
                Marker(
                  markerId: const MarkerId('school'),
                  position: school,
                  icon: icons?[MapPinColour.primary] ?? BitmapDescriptor.defaultMarker,
                  infoWindow: const InfoWindow(title: 'School'),
                ),
              if (busAt != null)
                Marker(
                  markerId: const MarkerId('bus'),
                  position: busAt,
                  icon: icons?[busPinColour(bus!)] ?? BitmapDescriptor.defaultMarker,
                  // Above the stops: the bus often sits right on one, and
                  // the thing somebody opened this for is the bus.
                  zIndexInt: 2,
                  infoWindow: InfoWindow(title: trip.vehicleName, snippet: lastSeenLabel(bus!.ageSeconds)),
                ),
              for (final stop in placed)
                Marker(
                  markerId: MarkerId('stop-${stop.id}'),
                  position: _pointOf(stop)!,
                  icon: icons?[stopPinColour(stop, next)] ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(
                    title: '${stop.sequenceNumber}. ${stop.name}',
                    snippet: stop.id == next?.id && etaSeconds != null
                        ? '${stopStateLabel(stop, next)} - ${minutesLabel(etaSeconds!)} away'
                        : stopStateLabel(stop, next),
                  ),
                ),
            },
            polylines: _lines(placed, school),
            // Opened on the whole trip rather than on the first stop at a
            // guessed zoom, which leaves a long route running off the edge.
            onMapCreated: (controller) => fitCamera(controller, [..._framed(placed, school), ?busAt]),
          ),
        ),
        const SizedBox(height: 6),
        _Legend(trip: trip, placed: placed.length, next: next, bus: bus),
      ],
    );
  }

  /// The road, or straight lines standing in for it - the same rule the
  /// route map follows, so the two never disagree about the same route.
  Set<Polyline> _lines(List<TripStop> placed, LatLng? school) {
    final road = trip.path.isCurrent ? decodePolyline(trip.path.polyline) : const <LatLng>[];

    if (road.length > 1) {
      return {Polyline(polylineId: const PolylineId('road'), points: road, width: 5, color: const Color(0xFF2563EB))};
    }

    final straight = [for (final stop in placed) _pointOf(stop)!, ?school];

    if (straight.length < 2) return const {};

    return {
      Polyline(
        polylineId: const PolylineId('straight'),
        points: straight,
        width: 3,
        color: const Color(0xFF94A3B8),
        patterns: [PatternItem.dash(20), PatternItem.gap(12)],
      ),
    };
  }

  /// Everything the map has to hold: the road where there is one, and the
  /// places otherwise. The road, not the stops, because a road can swing
  /// well outside the box its stops sit in.
  List<LatLng> _framed(List<TripStop> placed, LatLng? school) {
    final road = trip.path.isCurrent ? decodePolyline(trip.path.polyline) : const <LatLng>[];

    if (road.length > 1) return road;

    return [for (final stop in placed) _pointOf(stop)!, ?school];
  }

  LatLng? _pointOf(TripStop stop) => _point(stop.latitude, stop.longitude);

  LatLng? _schoolPoint() => _point(trip.schoolLatitude, trip.schoolLongitude);

  LatLng? _busPoint() => bus == null ? null : busAt ?? busPointOf(bus!);

  /// Public for [TripMapCard], which glides the pin between two of these.
  static LatLng? busPointOf(BusPosition bus) => _point(bus.latitude, bus.longitude);

  /// Null unless both halves are there and both are on the earth. A stop
  /// with half a coordinate points nowhere; drawn at (0, 0) it would sit
  /// off the coast of Africa and look deliberate.
  static LatLng? _point(String? latitude, String? longitude) {
    final lat = double.tryParse(latitude ?? '');
    final lng = double.tryParse(longitude ?? '');

    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;

    return LatLng(lat, lng);
  }

  static LatLng _centre(List<TripStop> placed, LatLng? school) {
    if (placed.isNotEmpty) return _point(placed.first.latitude, placed.first.longitude)!;

    return school ?? const LatLng(22.351, 78.667);
  }
}

/// The stop the bus is heading for: the first one it has not reached.
///
/// Only while the trip is running. A finished trip has no next stop even
/// when it ended with stops unreached - which happens, and drawing one of
/// them as "next" would say the bus is still on its way there.
TripStop? nextStop(TransportTrip trip) {
  if (!trip.isInProgress) return null;

  for (final stop in trip.stops) {
    if (!stop.reached) return stop;
  }

  return null;
}

/// Reached, next, or still to come.
///
/// Separated from the marker so it can be tested: a [BitmapDescriptor] has
/// no value equality, so a test that compares two markers' icons passes
/// whatever the rule underneath it says.
MapPinColour stopPinColour(TripStop stop, TripStop? next) {
  if (stop.reached) return MapPinColour.done;
  if (stop.id == next?.id) return MapPinColour.muted;

  return MapPinColour.secondary;
}

/// Where the bus is, or where it was a while ago.
///
/// The server decides what counts as a while - it knows when the position
/// was recorded and the app only knows what it was told - so this reads
/// [BusPosition.isStale] rather than doing the arithmetic again.
MapPinColour busPinColour(BusPosition bus) => bus.isStale ? MapPinColour.busStale : MapPinColour.bus;

/// The same three states in words, for the pin's info window.
String stopStateLabel(TripStop stop, TripStop? next) {
  if (stop.reached) return 'Reached';
  if (stop.id == next?.id) return 'Next stop';

  return 'Still to come';
}

/// What the colours mean, and anything the map could not draw.
class _Legend extends StatelessWidget {
  const _Legend({required this.trip, required this.placed, required this.next, required this.bus});

  final TransportTrip trip;
  final int placed;
  final TripStop? next;
  final BusPosition? bus;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final small = Theme.of(context).textTheme.bodySmall;
    final unplaced = trip.stops.length - placed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final entry in [
              // Named by its vehicle, and told apart from the stops by
              // being the only thing on the map that moves. The last-seen
              // words are added only when the pin is greyed, because
              // "greyed" means nothing to somebody who has never seen it
              // ungreyed - the Bus location card above says it in full
              // either way, and repeating that under every map would be
              // the same sentence twice.
              if (bus != null)
                (
                  busPinColour(bus!),
                  bus!.isStale
                      ? '${trip.vehicleName} - ${lastSeenLabel(bus!.ageSeconds).toLowerCase()}'
                      : trip.vehicleName,
                ),
              const (MapPinColour.done, 'Reached'),
              const (MapPinColour.muted, 'Next stop'),
              const (MapPinColour.secondary, 'Still to come'),
              const (MapPinColour.primary, 'School'),
            ])
              // "Next stop" is left out when there is not one, rather than
              // naming a colour nothing on the map is drawn in.
              if (entry.$1 != MapPinColour.muted || next != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: entry.$1.colour, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(entry.$2, style: small?.copyWith(color: colors.muted)),
                  ],
                ),
          ],
        ),
        if (trip.path.needsExplaining) ...[
          const SizedBox(height: 4),
          Text(_road(), style: small?.copyWith(color: colors.muted)),
        ],
        if (unplaced > 0) ...[
          const SizedBox(height: 4),
          Text(
            unplaced == 1
                ? '1 stop has no location, so it is not on the map.'
                : '$unplaced stops have no location, so they are not on the map.',
            style: small?.copyWith(color: colors.warning),
          ),
        ],
      ],
    );
  }

  String _road() {
    return switch (trip.path.status) {
      RoutePathStatus.stale => 'The route changed since this road was worked out; the dashed line is the order.',
      RoutePathStatus.failed => 'The road could not be worked out, so the dashed line is the order of the stops.',
      _ => 'The road has not been worked out yet; the dashed line is the order of the stops.',
    };
  }
}

/// The trip map with the bus on it, kept up to date.
///
/// Split from [TripMap] so the map itself takes a plain position and can be
/// tested without a repository behind it. This is the half that knows where
/// the position comes from: the same fifteen-second poll the Bus location
/// card uses, shared through the provider rather than asked for twice.
///
/// **The pin glides.** Each new position arrives about fifteen seconds
/// after the last, often a few hundred metres on; a pin that jumped there
/// would hop along the route and cut its corners. Instead it is moved along
/// the road from where it was drawn to the new position over the next
/// [glideOver] - about the time until the one after - so it is always on
/// its way somewhere and keeps to the streets (docs/maps.md, "A bus that
/// glides"). The first position, and a jump too long to be driving, are
/// drawn where they are.
///
/// A trip that is not running is not polled at all - there is nowhere for
/// its bus to have moved to, and the stop marks already say where it went.
class TripMapCard extends ConsumerStatefulWidget {
  const TripMapCard({super.key, required this.trip});

  final TransportTrip trip;

  /// How long each glide takes: the gap between two positions.
  static const glideOver = TripLiveLocationNotifier.pollInterval;

  /// Further than this between two positions is not driving - a phone that
  /// was out of signal, or a trip restarted elsewhere - and is not glided.
  static const longestGlideMetres = 2000.0;

  /// How often the pin is moved while gliding. A map redrawn sixty times a
  /// second costs the office computer more than the eye can tell apart.
  static const step = Duration(milliseconds: 100);

  @override
  ConsumerState<TripMapCard> createState() => _TripMapCardState();
}

class _TripMapCardState extends ConsumerState<TripMapCard> {
  LatLng? _drawn;
  RoadGlide? _glide;
  int _steps = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// A new position from the server: glide to it from wherever the pin is.
  void _arrived(BusPosition? position) {
    final target = position == null ? null : TripMap.busPointOf(position);
    final from = _drawn;

    if (target == null || from == null) {
      _stop(target);
      return;
    }

    final glide = RoadGlide.between(from, target, decodePolyline(widget.trip.path.polyline));
    if (glide.metres == 0 || glide.metres > TripMapCard.longestGlideMetres) {
      _stop(target);
      return;
    }

    _glide = glide;
    _steps = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(TripMapCard.step, (_) => _tick());
  }

  void _tick() {
    final glide = _glide;
    if (!mounted || glide == null) return;

    // Counted in steps rather than read off the clock: the same on screen,
    // and a test can move it.
    _steps++;
    final fraction = _steps * TripMapCard.step.inMilliseconds / TripMapCard.glideOver.inMilliseconds;
    setState(() => _drawn = glide.at(fraction));
    if (fraction >= 1) _stop(_drawn);
  }

  void _stop(LatLng? at) {
    _ticker?.cancel();
    _ticker = null;
    _glide = null;
    if (mounted) setState(() => _drawn = at);
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.trip.isInProgress;

    if (running) {
      ref.listen(tripLiveLocationProvider(widget.trip.id), (previous, next) => _arrived(next.value?.position));
    }

    final live = running ? ref.watch(tripLiveLocationProvider(widget.trip.id)).value : null;
    final position = live?.position;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        // Loading and failure are not the map's business: the Bus location
        // card above it already says both, and a map that disappeared every
        // time a poll failed would be worse than one without a bus on it.
        child: TripMap(
          trip: widget.trip,
          bus: position,
          busAt: _drawn ?? (position == null ? null : TripMap.busPointOf(position)),
          etaSeconds: live?.nextStop?.etaSeconds,
        ),
      ),
    );
  }
}
