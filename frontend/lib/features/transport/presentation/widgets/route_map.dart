import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../maps/data/polyline.dart';
import '../../../maps/presentation/app_map.dart';
import '../../../maps/presentation/fit_bounds.dart';
import '../../../maps/presentation/map_pin_icons.dart';
import '../../data/models/transport_route.dart';

/// A route's stops and the road between them (docs/maps.md, M2).
///
/// **The line is drawn whatever state the road is in.** A current road is
/// drawn solid; while one is being worked out, or after Google refused,
/// straight lines are drawn between the stops instead and the screen says
/// which it is looking at. A straight line through the right stops in the
/// right order tells somebody most of what they opened the map for, and is
/// a great deal better than an empty map.
class RouteMap extends ConsumerWidget {
  const RouteMap({super.key, required this.route, this.selectedStopId, this.onSelectStop, this.height = 320});

  final TransportRoute route;

  /// The stop whose row is highlighted in the list beside the map.
  final int? selectedStopId;
  final void Function(TransportStop stop)? onSelectStop;

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(mapPinIconsProvider).value;
    final placed = [
      for (final stop in route.stops)
        if (_pointOf(stop) != null) stop,
    ];
    final school = _schoolPoint();

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
                  infoWindow: InfoWindow(title: route.schoolName ?? 'School'),
                ),
              for (final stop in placed)
                Marker(
                  markerId: MarkerId('stop-${stop.id}'),
                  position: _pointOf(stop)!,
                  icon: icons?[MapPinColour.secondary] ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(title: '${stop.sequenceNumber}. ${stop.name}'),
                  onTap: onSelectStop == null ? null : () => onSelectStop!(stop),
                ),
            },
            polylines: _lines(placed, school),
            // Opened on the whole route rather than on the first stop at a
            // guessed zoom, which leaves a long route running off the edge.
            onMapCreated: (controller) => fitCamera(controller, _framed(placed, school)),
          ),
        ),
        const SizedBox(height: 6),
        _PathNote(route: route, placed: placed.length, totalStops: route.stops.length),
      ],
    );
  }

  /// The road, or straight lines standing in for it.
  Set<Polyline> _lines(List<TransportStop> placed, LatLng? school) {
    final road = route.path.isCurrent ? decodePolyline(route.path.polyline) : const <LatLng>[];

    if (road.length > 1) {
      return {Polyline(polylineId: const PolylineId('road'), points: road, width: 5, color: const Color(0xFF2563EB))};
    }

    // The stops in order, then the school - the same places the road joins,
    // so the stand-in and the real thing are never a different route.
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
  List<LatLng> _framed(List<TransportStop> placed, LatLng? school) {
    final road = route.path.isCurrent ? decodePolyline(route.path.polyline) : const <LatLng>[];

    if (road.length > 1) return road;

    return [for (final stop in placed) _pointOf(stop)!, ?school];
  }

  LatLng? _pointOf(TransportStop stop) => _point(stop.latitude, stop.longitude);

  LatLng? _schoolPoint() => _point(route.schoolLatitude, route.schoolLongitude);

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

  static LatLng _centre(List<TransportStop> placed, LatLng? school) {
    if (placed.isNotEmpty) return _point(placed.first.latitude, placed.first.longitude)!;

    return school ?? const LatLng(22.351, 78.667);
  }
}

/// What the line beneath the map is, and what to do about it.
class _PathNote extends ConsumerWidget {
  const _PathNote({required this.route, required this.placed, required this.totalStops});

  final TransportRoute route;
  final int placed;
  final int totalStops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final unplaced = totalStops - placed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_say(), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
        if (unplaced > 0)
          Text(
            unplaced == 1
                ? '1 stop has no location yet, so it is not on the map or the line.'
                : '$unplaced stops have no location yet, so they are not on the map or the line.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.warning),
          ),
        if (route.schoolLatitude == null)
          Text(
            'The school has no location, so the road cannot reach it. Set it on the school.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.warning),
          ),
      ],
    );
  }

  String _say() {
    if (placed < 2 && route.schoolLatitude == null) return 'Place at least two of these on the map to draw a route.';

    return switch (route.path.status) {
      RoutePathStatus.ok when route.path.polyline != null => _road(),
      RoutePathStatus.stale => 'The stops changed. The road is being worked out; the dashed line is the order.',
      RoutePathStatus.failed =>
        'The road could not be worked out: ${route.path.failureReason ?? 'Google could not be reached.'}',
      _ => 'The road has not been worked out yet; the dashed line is the order of the stops.',
    };
  }

  String _road() {
    final km = (route.path.distanceM ?? 0) / 1000;
    final minutes = ((route.path.durationS ?? 0) / 60).round();

    return 'By road: ${km.toStringAsFixed(1)} km, about $minutes min.';
  }
}
