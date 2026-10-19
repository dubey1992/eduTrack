import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../maps/presentation/app_map.dart';
import '../../maps/presentation/map_pin_icons.dart';
import '../data/models/school_pin.dart';
import '../data/school_locations_repository.dart';

/// The schools on a map (docs/maps.md, M1d).
///
/// A Super Admin sees the platform; a Group Admin sees their group. Which
/// schools arrive is the server's business - the same rule as the list, so
/// the map can never show a school the list would not.
///
/// **The schools with no coordinates are listed beside it.** They are the
/// work the map exists to prompt, and a map that quietly left them out
/// would hide exactly the thing somebody opened it to find.
class SchoolsMapView extends ConsumerStatefulWidget {
  const SchoolsMapView({super.key, required this.onOpen});

  /// Opening a school from its pin. The map knows which school; what to do
  /// about it belongs to the screen.
  final void Function(int schoolId) onOpen;

  @override
  ConsumerState<SchoolsMapView> createState() => _SchoolsMapViewState();
}

class _SchoolsMapViewState extends ConsumerState<SchoolsMapView> {
  GoogleMapController? _map;

  /// Which pin's card is open, so tapping the same one twice closes it and
  /// the list beside the map can highlight it.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(schoolLocationsProvider);

    return AsyncValueView<SchoolLocations>(
      value: locations,
      onRetry: () => ref.invalidate(schoolLocationsProvider),
      data: (context, locations) => _Found(
        // Null until the pins have been drawn. Google's own marker stands
        // in meanwhile, so a map never waits on its decoration.
        icons: ref.watch(mapPinIconsProvider).value,
        locations: locations,
        selected: _selected,
        onSelect: _select,
        onOpen: widget.onOpen,
        onMapCreated: (controller) {
          _map = controller;
          _frameEverything(locations);
        },
      ),
    );
  }

  void _select(SchoolPin pin) {
    setState(() => _selected = _selected == pin.id ? null : pin.id);
    _map?.animateCamera(CameraUpdate.newLatLng(LatLng(pin.latitude, pin.longitude)));
  }

  /// Opens showing every pin at once rather than one arbitrary school.
  ///
  /// A group's branches are a few miles apart and a platform's schools are
  /// a continent apart, so a fixed zoom is wrong for one of them whichever
  /// is chosen.
  void _frameEverything(SchoolLocations locations) {
    if (locations.placed.isEmpty) return;

    if (locations.placed.length == 1) {
      final only = locations.placed.single;
      _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(only.latitude, only.longitude), 14));
      return;
    }

    _map?.animateCamera(CameraUpdate.newLatLngBounds(_around(locations.placed), 48));
  }

  /// The box every pin sits in. Google refuses bounds whose corners are the
  /// same point, which is what two schools at one address would produce, so
  /// it is nudged apart.
  static LatLngBounds _around(List<SchoolPin> pins) {
    var south = pins.first.latitude;
    var north = pins.first.latitude;
    var west = pins.first.longitude;
    var east = pins.first.longitude;

    for (final pin in pins) {
      south = pin.latitude < south ? pin.latitude : south;
      north = pin.latitude > north ? pin.latitude : north;
      west = pin.longitude < west ? pin.longitude : west;
      east = pin.longitude > east ? pin.longitude : east;
    }

    const nudge = 0.001;

    return LatLngBounds(southwest: LatLng(south - nudge, west - nudge), northeast: LatLng(north + nudge, east + nudge));
  }
}

class _Found extends StatelessWidget {
  const _Found({
    required this.icons,
    required this.locations,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onMapCreated,
  });

  final Map<MapPinColour, BitmapDescriptor>? icons;
  final SchoolLocations locations;
  final int? selected;
  final void Function(SchoolPin pin) onSelect;
  final void Function(int schoolId) onOpen;
  final void Function(GoogleMapController controller) onMapCreated;

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(32), child: Text('No schools yet. Add one and it will appear here.')),
      );
    }

    final chosen = locations.placed.where((pin) => pin.id == selected).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (locations.moreThanShown) _TooMany(shown: locations.placed.length + locations.unplaced.length),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    AppMap(
                      view: AppMapView(
                        centre: locations.placed.isEmpty
                            ? _theCountry
                            : LatLng(locations.placed.first.latitude, locations.placed.first.longitude),
                        zoom: 4,
                        markers: {
                          for (final pin in locations.placed)
                            Marker(
                              markerId: MarkerId('school-${pin.id}'),
                              position: LatLng(pin.latitude, pin.longitude),
                              icon: icons?[schoolPinColour(pin)] ?? BitmapDescriptor.defaultMarker,
                              onTap: () => onSelect(pin),
                            ),
                        },
                        onMapCreated: onMapCreated,
                      ),
                    ),
                    if (chosen != null)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _SchoolCard(pin: chosen, onOpen: () => onOpen(chosen.id)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _Beside(locations: locations, selected: selected, onSelect: onSelect, onOpen: onOpen),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _theCountry = LatLng(22.351, 78.667);
}

/// What colour a school's pin is, in order of what somebody is looking
/// for: switched off first, then a branch, then a school in its own right.
///
/// Returns the *choice* rather than a drawn pin, and is public, because a
/// `BitmapDescriptor` has no value equality: two built the same way compare
/// unequal, so a test comparing descriptors passes whatever this does. This
/// is the rule, and it can be asserted on.
MapPinColour schoolPinColour(SchoolPin pin) {
  if (!pin.isActive) return MapPinColour.muted;

  return pin.isBranch ? MapPinColour.secondary : MapPinColour.primary;
}

class _TooMany extends StatelessWidget {
  const _TooMany({required this.shown});

  final int shown;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.warningContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(
        'Showing the first $shown schools. There are more - use the list to find a particular one.',
        style: TextStyle(color: colors.onWarningContainer),
      ),
    );
  }
}

/// The list down the side: what is on the map, and what is not on it yet.
class _Beside extends StatelessWidget {
  const _Beside({required this.locations, required this.selected, required this.onSelect, required this.onOpen});

  final SchoolLocations locations;
  final int? selected;
  final void Function(SchoolPin pin) onSelect;
  final void Function(int schoolId) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ListView(
      children: [
        if (locations.unplaced.isNotEmpty) ...[
          Text('Not on the map yet (${locations.unplaced.length})', style: Theme.of(context).textTheme.titleSmall),
          Text(
            'These schools have no coordinates. Open one and use the map in its form to place it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 4),
          for (final school in locations.unplaced)
            ListTile(
              dense: true,
              leading: Icon(Icons.location_off_outlined, size: 18, color: colors.muted),
              title: Text(school.name),
              onTap: () => onOpen(school.id),
            ),
          const Divider(height: 24),
        ],
        Text('On the map (${locations.placed.length})', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final pin in locations.placed)
          ListTile(
            dense: true,
            selected: pin.id == selected,
            leading: Icon(
              pin.isBranch ? Icons.account_tree_outlined : Icons.apartment_outlined,
              size: 18,
              color: pin.isActive ? null : colors.warning,
            ),
            title: Text(pin.name),
            subtitle: pin.city.isEmpty ? null : Text(pin.city),
            onTap: () => onSelect(pin),
          ),
      ],
    );
  }
}

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({required this.pin, required this.onOpen});

  final SchoolPin pin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pin.name, style: Theme.of(context).textTheme.titleSmall),
            if (pin.city.isNotEmpty)
              Text(pin.city, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
            Text(
              pin.isBranch ? 'Branch' : 'School',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
            if (!pin.isActive)
              Text('Switched off', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.warning)),
            const SizedBox(height: 4),
            TextButton(onPressed: onOpen, child: const Text('Open')),
          ],
        ),
      ),
    );
  }
}
