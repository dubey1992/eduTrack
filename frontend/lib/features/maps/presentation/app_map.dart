import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../data/maps_config.dart';
import '../data/maps_script.dart';

/// Where the map starts, and what it holds.
///
/// A plain description rather than Google's own types at the call sites, so
/// a screen that wants a map says what it wants to show and nothing about
/// how it is drawn.
class AppMapView {
  const AppMapView({
    required this.centre,
    this.zoom = 14,
    this.markers = const {},
    this.polylines = const {},
    this.onTap,
    this.onMapCreated,
  });

  final LatLng centre;
  final double zoom;
  final Set<Marker> markers;
  final Set<Polyline> polylines;

  /// A point somebody clicked. Null means the map is for looking at.
  final void Function(LatLng position)? onTap;

  final void Function(GoogleMapController controller)? onMapCreated;
}

/// How a map gets drawn. There is one real implementation and one fake.
///
/// The fake is why this exists: `GoogleMap` draws nothing under
/// `flutter test` - there is no platform view - so every widget test of
/// every screen that holds a map would need a browser. Screens depend on
/// this, tests override it, and what they are testing is the screen rather
/// than Google's widget.
abstract class MapRenderer {
  Widget build(BuildContext context, AppMapView view);
}

class GoogleMapRenderer implements MapRenderer {
  const GoogleMapRenderer();

  @override
  Widget build(BuildContext context, AppMapView view) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: view.centre, zoom: view.zoom),
      markers: view.markers,
      polylines: view.polylines,
      onTap: view.onTap,
      onMapCreated: view.onMapCreated,
      // A map inside a scrolling page: without this, dragging the map
      // scrolls the page instead and the map cannot be panned at all.
      gestureRecognizers: const {},
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
    );
  }
}

final mapRendererProvider = Provider<MapRenderer>((ref) => const GoogleMapRenderer());

/// A map, or a plain statement that there is not one.
///
/// **Never an error, and never nothing.** A map is an improvement on a
/// screen rather than the screen itself: the schools list, the stop list and
/// the trip all work without one. With no key configured, with Google
/// unreachable, or with a script an ad blocker refused, this says so in the
/// space the map would have taken and the screen carries on around it.
class AppMap extends ConsumerWidget {
  const AppMap({super.key, required this.view, this.height});

  final AppMapView view;

  /// Null fills whatever room the parent gives it.
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapsConfigProvider);

    return SizedBox(
      height: height,
      child: config.when(
        loading: () => const _MapBox(child: Center(child: CircularProgressIndicator())),
        error: (_, _) => const MapUnavailable(),
        data: (config) => config.available ? _ReadyMap(config: config, view: view) : const MapUnavailable(),
      ),
    );
  }
}

/// Waits for the platform to be able to draw a map before asking it to.
///
/// On the web the Maps JavaScript API has to be on the page first; creating
/// a map before it is throws, and the screen shows a red box. On Android
/// this resolves at once.
class _ReadyMap extends ConsumerStatefulWidget {
  const _ReadyMap({required this.config, required this.view});

  final MapsConfig config;
  final AppMapView view;

  @override
  ConsumerState<_ReadyMap> createState() => _ReadyMapState();
}

class _ReadyMapState extends ConsumerState<_ReadyMap> {
  late final Future<void> _ready = ensureMapsReady(widget.config.browserKey);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MapBox(child: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) return const MapUnavailable();

        return ref.watch(mapRendererProvider).build(context, widget.view);
      },
    );
  }
}

/// What stands in for a map when there cannot be one.
///
/// It names the reason plainly instead of showing a broken frame, because
/// the person reading it is usually an administrator who can do something
/// about it - and because every screen that holds a map also holds the list
/// the map was illustrating.
class MapUnavailable extends StatelessWidget {
  const MapUnavailable({super.key});

  static const message = 'Map unavailable - no Google Maps key is configured.';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return _MapBox(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, color: colors.muted),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapBox extends StatelessWidget {
  const _MapBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
