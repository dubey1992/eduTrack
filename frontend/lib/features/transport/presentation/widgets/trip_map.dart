import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../maps/data/polyline.dart';
import '../../../maps/presentation/app_map.dart';
import '../../../maps/presentation/fit_bounds.dart';
import '../../../maps/presentation/map_pin_icons.dart';
import '../../data/models/transport_route.dart';
import '../../data/models/transport_trip.dart';

/// Where a trip goes, and how far along it is (docs/maps.md, M3).
///
/// The road the route follows, the school at the end of it, and the stops
/// coloured by what the trip has done with them: reached, heading there
/// next, still to come. **None of this needs the bus to be sharing its
/// position** - it is drawn from the stop marks the trip already records,
/// so a trip that finished last week reads the same way as one running now.
class TripMap extends ConsumerWidget {
  const TripMap({super.key, required this.trip, this.height = 320});

  final TransportTrip trip;
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
              for (final stop in placed)
                Marker(
                  markerId: MarkerId('stop-${stop.id}'),
                  position: _pointOf(stop)!,
                  icon: icons?[stopPinColour(stop, next)] ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(
                    title: '${stop.sequenceNumber}. ${stop.name}',
                    snippet: stopStateLabel(stop, next),
                  ),
                ),
            },
            polylines: _lines(placed, school),
            // Opened on the whole trip rather than on the first stop at a
            // guessed zoom, which leaves a long route running off the edge.
            onMapCreated: (controller) => fitCamera(controller, _framed(placed, school)),
          ),
        ),
        const SizedBox(height: 6),
        _Legend(trip: trip, placed: placed.length, next: next),
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

/// The same three states in words, for the pin's info window.
String stopStateLabel(TripStop stop, TripStop? next) {
  if (stop.reached) return 'Reached';
  if (stop.id == next?.id) return 'Next stop';

  return 'Still to come';
}

/// What the colours mean, and anything the map could not draw.
class _Legend extends StatelessWidget {
  const _Legend({required this.trip, required this.placed, required this.next});

  final TransportTrip trip;
  final int placed;
  final TripStop? next;

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
            for (final entry in const [
              (MapPinColour.done, 'Reached'),
              (MapPinColour.muted, 'Next stop'),
              (MapPinColour.secondary, 'Still to come'),
              (MapPinColour.primary, 'School'),
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
