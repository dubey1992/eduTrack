import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../data/places_repository.dart';
import 'app_map.dart';
import 'map_pin_icons.dart';
import 'distance.dart';

/// Putting something on the map: a school, and later a bus stop
/// (docs/maps.md, M1).
///
/// Three ways to set the same pair of numbers, because the people doing it
/// have different things to hand. Somebody onboarding a school knows its
/// address; somebody placing a stop knows the corner it is on and will
/// click it; somebody migrating from a spreadsheet has the coordinates
/// already. So: search, click or drag, or type.
///
/// **The boxes are the source of truth, not the pin.** They are what the
/// form sends, they are what the server validates, and they keep working
/// when there is no map at all - which is the state the product is in until
/// a key is configured. The map writes into them; it never replaces them.
class LocationPicker extends ConsumerStatefulWidget {
  const LocationPicker({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.child,
    this.near,
    this.origin,
    this.originLabel,
    this.height = 260,
  });

  /// The boxes this picker fills in. Owned by the form, not by this.
  final TextEditingController latitude;
  final TextEditingController longitude;

  /// The coordinate boxes themselves, drawn under the map. Passed in rather
  /// than built here so the school form and the stop form can each keep
  /// their own labels and their own server-side errors.
  final Widget child;

  /// Where to look first when there is nothing to show yet, and what to bias
  /// address search towards - the school, when placing one of its stops.
  final LatLng? near;

  /// The place everything here is arranged around - the school, when
  /// placing one of its stops. Pinned in its own colour and measured
  /// against, so "is this the right street?" can be answered without
  /// leaving the dialog.
  ///
  /// Null when the thing being placed *is* the origin: the school form
  /// would otherwise draw two pins for one school.
  final LatLng? origin;

  /// What to call it in the distance line. "the school" when unset.
  final String? originLabel;

  final double height;

  @override
  ConsumerState<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<LocationPicker> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  List<PlaceSuggestion> _suggestions = const [];
  Timer? _debounce;
  bool _searching = false;

  /// What the point the pin is on is called. Shown under the map so somebody
  /// can tell at a glance that they clicked the right street.
  String _label = '';

  /// A map centred on the first thing it was given would jump back there
  /// every time the boxes changed, so the controller is kept and moved.
  GoogleMapController? _map;

  /// Google charges per search and nobody means the word they are halfway
  /// through typing.
  static const _settle = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    widget.latitude.addListener(_typed);
    widget.longitude.addListener(_typed);
  }

  @override
  void dispose() {
    widget.latitude.removeListener(_typed);
    widget.longitude.removeListener(_typed);
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Somebody typing coordinates by hand moves the pin, so the two never
  /// disagree about where the thing is.
  void _typed() {
    if (mounted) setState(() {});
  }

  LatLng? get _pinned {
    final latitude = double.tryParse(widget.latitude.text.trim());
    final longitude = double.tryParse(widget.longitude.text.trim());

    if (latitude == null || longitude == null) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;

    return LatLng(latitude, longitude);
  }

  void _moveTo(LatLng position, {String label = ''}) {
    // Seven decimals is what the column stores; more is noise, and it makes
    // the boxes unreadable.
    widget.latitude.text = position.latitude.toStringAsFixed(7);
    widget.longitude.text = position.longitude.toStringAsFixed(7);

    setState(() => _label = label);
    // Zoom as well as pan. The map opens showing the whole country, and
    // panning alone leaves a pin somebody chose from an address sitting in
    // the middle of a continent, with no way to see what it is next to.
    _map?.animateCamera(CameraUpdate.newLatLngZoom(position, _closeUp));
  }

  void _searchChanged(String query) {
    _debounce?.cancel();

    if (query.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }

    _debounce = Timer(_settle, () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);

    final near = _pinned ?? widget.near;
    final found = await ref
        .read(placesRepositoryProvider)
        .search(query, nearLatitude: near?.latitude, nearLongitude: near?.longitude);

    if (!mounted) return;

    setState(() {
      _suggestions = found;
      _searching = false;
    });
  }

  Future<void> _pick(PlaceSuggestion suggestion) async {
    _searchFocus.unfocus();
    setState(() {
      _suggestions = const [];
      _searching = true;
    });

    final place = await ref.read(placesRepositoryProvider).find(suggestion.placeId);

    if (!mounted) return;

    setState(() => _searching = false);

    // Null means the lookup failed. The pin stays where it was rather than
    // moving somewhere nobody chose.
    if (place == null) return;

    _searchController.text = place.address.isEmpty ? place.label : place.address;
    _moveTo(LatLng(place.latitude, place.longitude), label: place.address);
  }

  Future<void> _droppedAt(LatLng position) async {
    _moveTo(position);

    final address = await ref.read(placesRepositoryProvider).describe(position.latitude, position.longitude);

    if (mounted && address.isNotEmpty) setState(() => _label = address);
  }

  void _clear() {
    widget.latitude.clear();
    widget.longitude.clear();
    _searchController.clear();
    setState(() {
      _label = '';
      _suggestions = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pinned = _pinned;

    final icons = ref.watch(mapPinIconsProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SearchBox(
          controller: _searchController,
          focusNode: _searchFocus,
          searching: _searching,
          onChanged: _searchChanged,
        ),
        if (_suggestions.isNotEmpty) _Suggestions(suggestions: _suggestions, onPick: _pick),
        const SizedBox(height: 10),
        AppMap(
          height: widget.height,
          view: AppMapView(
            centre: pinned ?? widget.near ?? _theCountry,
            zoom: pinned == null ? 4 : _closeUp,
            markers: {
              // The origin first, so the pin being placed draws over it
              // when the two are close.
              if (widget.origin != null)
                Marker(
                  markerId: const MarkerId('origin'),
                  position: widget.origin!,
                  icon: icons?[MapPinColour.primary] ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(title: widget.originLabel ?? 'School'),
                ),
              if (pinned != null)
                Marker(
                  markerId: const MarkerId('picked'),
                  position: pinned,
                  // Blue against the origin's red: which pin is the thing
                  // being placed should not need a second look.
                  icon: icons?[MapPinColour.secondary] ?? BitmapDescriptor.defaultMarker,
                  draggable: true,
                  onDragEnd: _droppedAt,
                ),
            },
            onTap: _droppedAt,
            onMapCreated: (controller) => _map = controller,
          ),
        ),
        const SizedBox(height: 6),
        // How far it is from the origin, where there is one. A number
        // rather than two pins to judge by eye: the difference between the
        // right street and the wrong city is what this catches, and the
        // server refuses anything beyond 100 km anyway.
        if (widget.origin != null && pinned != null) ...[
          Row(
            children: [
              Icon(Icons.straighten, size: 14, color: colors.muted),
              const SizedBox(width: 6),
              // Expanded, because a school with a long name is the common
              // case and an overflowing row is a yellow-and-black bar.
              Expanded(
                child: Text(
                  '${formatDistance(distanceM(widget.origin!, pinned))} from '
                  '${widget.originLabel ?? 'the school'}, in a straight line',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                _label.isNotEmpty
                    ? _label
                    : pinned == null
                    ? 'Search for an address, or tap the map to drop a pin.'
                    : 'Drag the pin to adjust it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
            ),
            if (pinned != null)
              TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Remove pin'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        widget.child,
      ],
    );
  }

  /// Nothing placed yet: the whole country, zoomed out, rather than a
  /// convincing-looking pin on an arbitrary city.
  static const _theCountry = LatLng(22.351, 78.667);

  /// Close enough to see which side of the road the pin is on, which is the
  /// thing somebody is about to drag it to correct.
  static const _closeUp = 16.0;
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Search for an address',
        hintText: 'Station Road, Pune',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
        isDense: true,
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.onPick});

  final List<PlaceSuggestion> suggestions;
  final void Function(PlaceSuggestion suggestion) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final suggestion in suggestions)
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, size: 18),
              title: Text(suggestion.label),
              subtitle: suggestion.detail.isEmpty ? null : Text(suggestion.detail),
              onTap: () => onPick(suggestion),
            ),
        ],
      ),
    );
  }
}
