import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../maps/presentation/app_map.dart';
import '../../../maps/presentation/map_pin_icons.dart';
import '../../application/route_page_notifier.dart';
import '../bus_stop_form_dialog.dart';
import '../../data/models/bus_stop.dart';
import '../../application/transport_pickers.dart';
import 'submit_button.dart';

/// Drawing a route on the school's own map (docs/maps.md).
///
/// The point is the order of the stops, and an ordered thing is far easier
/// to get right by pointing at it than by typing twelve pairs of
/// coordinates into twelve dialogs. So: tap the map, the stop lands where
/// you tapped and joins the end of the run; the list beside it is the
/// route, in order, and can be renamed, reordered and pruned before any of
/// it is saved.
///
/// **Nothing exists until Save.** A route half-built on a screen is a
/// sketch; a route half-built in the database is a mess somebody has to
/// work out. The server takes the whole thing in one request and writes it
/// in one transaction.
///
/// Used from two places on purpose - the school's View Map, and Transport >
/// Routes - because a School Admin works in one and a Transport Manager in
/// the other, and two implementations would drift.
class RouteBuilderMap extends ConsumerStatefulWidget {
  const RouteBuilderMap({
    super.key,
    required this.schoolId,
    required this.schoolAt,
    this.schoolName,
    this.height = 420,
  });

  /// Which school the route belongs to. Null lets the server decide from
  /// the person signing in, which is what a single-school admin wants.
  final int? schoolId;

  /// Where to centre, and what the stops are measured against. Null for a
  /// school nobody has placed - the builder says so rather than dropping
  /// pins into the sea off Africa.
  final LatLng? schoolAt;

  final String? schoolName;
  final double height;

  @override
  ConsumerState<RouteBuilderMap> createState() => _RouteBuilderMapState();
}

/// One call on the way to being saved.
///
/// It holds a place from the school's list - the name and the position are
/// that place's - plus what belongs to this route: where in the run it
/// comes and when the bus is there (docs/maps.md).
class DraftStop {
  DraftStop({required this.place, this.pickupTime, this.dropTime});

  BusStop place;
  String? pickupTime;
  String? dropTime;

  String get name => place.name;

  LatLng get at => LatLng(double.parse(place.latitude), double.parse(place.longitude));

  Map<String, dynamic> toJson(int sequenceNumber) => {
    'bus_stop_id': place.id,
    'sequence_number': sequenceNumber,
    'pickup_time': pickupTime,
    'drop_time': dropTime,
  };
}

class _RouteBuilderMapState extends ConsumerState<RouteBuilderMap> {
  final _nameController = TextEditingController();
  final _stops = <DraftStop>[];

  bool _drawing = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<String> _stopProblems = const [];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _drawing = true;
      _stops.clear();
      _nameController.clear();
      _errorMessage = null;
      _stopProblems = const [];
    });
  }

  void _stop() {
    setState(() {
      _drawing = false;
      _stops.clear();
      _errorMessage = null;
      _stopProblems = const [];
    });
  }

  /// A tap on the map while drawing.
  ///
  /// It adds the place to the school's list **and** puts it on the route,
  /// because the list is the only way a stop exists now - and a place
  /// deserves a real name rather than "Stop 3", so the form opens straight
  /// away with the tapped position already in it.
  Future<void> _addStop(LatLng at) async {
    if (!_drawing) return;

    final made = await showDialog<BusStop>(
      context: context,
      builder: (_) => BusStopFormDialog(schoolId: widget.schoolId, at: at, returnsTheStop: true),
    );

    if (made == null || !mounted) return;

    setState(() => _stops.add(DraftStop(place: made)));
  }

  /// Or one the school already has, which is the common case once the list
  /// has anything in it.
  Future<void> _addExisting() async {
    final route = _stops.map((stop) => stop.place.id).toSet();
    final picked = await showDialog<BusStop>(
      context: context,
      builder: (_) => _PickABusStop(schoolId: widget.schoolId, already: route),
    );

    if (picked == null || !mounted) return;

    setState(() => _stops.add(DraftStop(place: picked)));
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _stops.length) return;

    setState(() {
      final moved = _stops.removeAt(from);
      _stops.insert(to, moved);
    });
  }

  /// The times this route calls at it. The name and the position are the
  /// bus stop's, and are changed under Transport > Bus Stops.
  Future<void> _times(int index) async {
    final edited = await showDialog<DraftStop>(
      context: context,
      builder: (_) => _StopDetailsDialog(stop: _stops[index]),
    );

    if (edited == null) return;

    setState(() => _stops[index] = edited);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    if (_isSubmitting) return;

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Give the route a name.');

      return;
    }

    if (_stops.isEmpty) {
      setState(() => _errorMessage = 'Tap the map to add at least one stop.');

      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _stopProblems = const [];
    });

    try {
      await ref
          .read(routePageNotifierProvider.notifier)
          .createRoute(
            schoolId: widget.schoolId,
            name: name,
            stops: [for (final (index, stop) in _stops.indexed) stop.toJson(index + 1)],
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name saved with ${_stops.length} stops.')));
      _stop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());

      if (mounted) {
        setState(() {
          // The server checks the batch for the two things only a batch can
          // get wrong - two stops sharing a name, or a place in the order -
          // and each message names the stop, so they go above the list.
          _stopProblems = failure.validationErrors['stops'] ?? const [];
          _errorMessage = _stopProblems.isEmpty ? failure.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.schoolAt;

    if (at == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined, color: context.appColors.muted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Place this school on the map first - a route is drawn around where the school is.'),
              ),
            ],
          ),
        ),
      );
    }

    final icons = ref.watch(mapPinIconsProvider).value;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final map = AppMap(
      height: widget.height,
      view: AppMapView(
        centre: _stops.isEmpty ? at : _stops.last.at,
        zoom: 14,
        onTap: _drawing ? _addStop : null,
        markers: {
          Marker(
            // The same id the school's own map uses, so the page has one
            // name for one pin whichever map is drawn.
            markerId: MarkerId(widget.schoolId == null ? 'school' : 'school-${widget.schoolId}'),
            position: at,
            icon: icons?[MapPinColour.primary] ?? BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(title: widget.schoolName ?? 'School'),
          ),
          for (final (index, stop) in _stops.indexed)
            Marker(
              markerId: MarkerId('draft-$index'),
              position: stop.at,
              icon: icons?[MapPinColour.secondary] ?? BitmapDescriptor.defaultMarker,
              infoWindow: InfoWindow(title: '${index + 1}. ${stop.name}'),
            ),
        },
        polylines: {
          if (_stops.length > 1)
            Polyline(
              polylineId: const PolylineId('draft'),
              points: [for (final stop in _stops) stop.at],
              color: Theme.of(context).colorScheme.primary,
              width: 4,
            ),
        },
      ),
    );

    final panel = _Panel(
      drawing: _drawing,
      stops: _stops,
      nameController: _nameController,
      isSubmitting: _isSubmitting,
      errorMessage: _errorMessage,
      stopProblems: _stopProblems,
      onStart: _start,
      onAddExisting: _addExisting,
      onCancel: _stop,
      onSave: _save,
      onRename: _times,
      onMove: _move,
      onRemove: (index) => setState(() => _stops.removeAt(index)),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: map),
                  const SizedBox(width: 16),
                  SizedBox(width: 320, child: panel),
                ],
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [map, const SizedBox(height: 16), panel]),
      ),
    );
  }
}

/// The route being built, beside the map it is being built on.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.drawing,
    required this.stops,
    required this.nameController,
    required this.isSubmitting,
    required this.errorMessage,
    required this.stopProblems,
    required this.onStart,
    required this.onAddExisting,
    required this.onCancel,
    required this.onSave,
    required this.onRename,
    required this.onMove,
    required this.onRemove,
  });

  final bool drawing;
  final List<DraftStop> stops;
  final TextEditingController nameController;
  final bool isSubmitting;
  final String? errorMessage;
  final List<String> stopProblems;
  final VoidCallback onStart;
  final VoidCallback onAddExisting;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final void Function(int index) onRename;
  final void Function(int from, int to) onMove;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (!drawing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Routes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Draw a route on this map: tap where each stop is, in the order the bus takes them.',
            style: TextStyle(color: colors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('new-route'),
            onPressed: onStart,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('New route'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Route name', hintText: 'e.g. North Loop', isDense: true),
          maxLength: 100,
        ),
        if (errorMessage != null) ...[
          Text(errorMessage!, style: TextStyle(color: colors.danger)),
          const SizedBox(height: 8),
        ],
        for (final problem in stopProblems) ...[
          Text(problem, style: TextStyle(color: colors.danger)),
          const SizedBox(height: 4),
        ],
        if (stops.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Tap the map to add a new stop, or pick one the school already has.',
              style: TextStyle(color: colors.muted),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: stops.length,
              itemBuilder: (context, index) => _StopRow(
                position: index + 1,
                stop: stops[index],
                onRename: () => onRename(index),
                onUp: index == 0 ? null : () => onMove(index, index - 1),
                onDown: index == stops.length - 1 ? null : () => onMove(index, index + 1),
                onRemove: () => onRemove(index),
              ),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('add-an-existing-stop'),
          onPressed: isSubmitting ? null : onAddExisting,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Add an existing stop'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton(onPressed: isSubmitting ? null : onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            SubmitButton(isSubmitting: isSubmitting, onPressed: onSave, label: 'Save route'),
          ],
        ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.position,
    required this.stop,
    required this.onRename,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final int position;
  final DraftStop stop;
  final VoidCallback onRename;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final times = [stop.pickupTime, stop.dropTime].whereType<String>().join(' · ');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 13, child: Text('$position', style: const TextStyle(fontSize: 12))),
      title: Text(stop.name, overflow: TextOverflow.ellipsis),
      subtitle: times.isEmpty ? null : Text(times, style: TextStyle(color: context.appColors.muted)),
      onTap: onRename,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.arrow_upward, size: 16), tooltip: 'Move up', onPressed: onUp),
          IconButton(icon: const Icon(Icons.arrow_downward, size: 16), tooltip: 'Move down', onPressed: onDown),
          IconButton(icon: const Icon(Icons.close, size: 16), tooltip: 'Remove', onPressed: onRemove),
        ],
      ),
    );
  }
}

/// When this route calls at a stop.
///
/// Not its name and not its position - those are the bus stop's, and are
/// changed under Transport > Bus Stops so every route using it follows
/// (docs/maps.md).
class _StopDetailsDialog extends StatefulWidget {
  const _StopDetailsDialog({required this.stop});

  final DraftStop stop;

  @override
  State<_StopDetailsDialog> createState() => _StopDetailsDialogState();
}

class _StopDetailsDialogState extends State<_StopDetailsDialog> {
  late String? _pickupTime = widget.stop.pickupTime;
  late String? _dropTime = widget.stop.dropTime;

  Future<void> _pick({required bool isPickup}) async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 30));

    if (picked == null) return;

    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

    setState(() => isPickup ? _pickupTime = value : _dropTime = value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.stop.name),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When the bus is here. The name and the place are the bus stop\'s - '
              'change them under Transport > Bus Stops.',
              style: TextStyle(color: context.appColors.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(isPickup: true),
                    icon: const Icon(Icons.login, size: 16),
                    label: Text(_pickupTime ?? 'Pickup'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(isPickup: false),
                    icon: const Icon(Icons.logout, size: 16),
                    label: Text(_dropTime ?? 'Drop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(DraftStop(place: widget.stop.place, pickupTime: _pickupTime, dropTime: _dropTime)),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// One of the school's bus stops this route does not already call at.
class _PickABusStop extends ConsumerWidget {
  const _PickABusStop({required this.schoolId, required this.already});

  final int? schoolId;
  final Set<int> already;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(busStopPickerProvider(schoolId));

    return AlertDialog(
      title: const Text('Add a stop'),
      content: SizedBox(
        width: 420,
        child: places.when(
          loading: () => const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          ),
          error: (_, _) => Text('Could not load the bus stops.', style: TextStyle(color: context.appColors.danger)),
          data: (all) {
            final offered = all.where((place) => !already.contains(place.id)).toList();

            if (offered.isEmpty) {
              return Text(
                all.isEmpty
                    ? 'This school has no bus stops yet. Tap the map to add the first one.'
                    : 'Every bus stop the school has is already on this route.',
                style: TextStyle(color: context.appColors.muted),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: offered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => ListTile(
                  title: Text(offered[index].name),
                  subtitle: offered[index].landmark == null ? null : Text(offered[index].landmark!),
                  onTap: () => Navigator.of(context).pop(offered[index]),
                ),
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}
