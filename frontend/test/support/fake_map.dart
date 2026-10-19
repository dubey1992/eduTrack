import 'package:edutrack_app/features/maps/data/maps_config.dart';
import 'package:edutrack_app/features/maps/presentation/app_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A map for widget tests (docs/maps.md, M1).
///
/// `GoogleMap` draws nothing under `flutter test` - there is no platform
/// view behind it - so every screen that holds a map would otherwise need a
/// browser to test at all. This draws a plain box in its place and records
/// what it was asked to show, which is the part a screen's test is actually
/// about: the right pins, in the right places, and what a tap does.
class FakeMapRenderer implements MapRenderer {
  AppMapView? lastView;
  int builds = 0;

  /// The markers the screen last asked for, by their id - which is how the
  /// screens name them, so a test can ask for "the pin for school 4".
  Map<String, Marker> get markersById => {
    for (final marker in lastView?.markers ?? const <Marker>{}) marker.markerId.value: marker,
  };

  Set<Polyline> get polylines => lastView?.polylines ?? const {};

  /// Pretends somebody clicked the map, so a test can check what follows.
  void tapAt(LatLng position) => lastView?.onTap?.call(position);

  @override
  Widget build(BuildContext context, AppMapView view) {
    lastView = view;
    builds++;

    return const ColoredBox(
      color: Color(0xFFDDE7F0),
      child: Center(child: Text('map')),
    );
  }
}

/// Overrides for a screen whose map should draw.
///
/// [renderer] is the fake, and the config is answered without a request, so
/// no test of a map screen depends on the server having a key.
List<Override> mapIsAvailable(FakeMapRenderer renderer) {
  return [
    mapRendererProvider.overrideWithValue(renderer),
    mapsConfigProvider.overrideWith((ref) async => const MapsConfig.withKey('test-browser-key')),
  ];
}

/// Overrides for the state the app is in before anybody sets a key up -
/// and the state it falls back to when Google cannot be reached.
List<Override> mapIsUnavailable() {
  return [mapsConfigProvider.overrideWith((ref) async => const MapsConfig.none())];
}
