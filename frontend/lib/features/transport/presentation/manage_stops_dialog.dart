import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../maps/presentation/location_picker.dart';
import '../../schools/presentation/widgets/coordinates_fields.dart';
import '../application/route_detail_notifier.dart';
import '../application/transport_pickers.dart';
import '../data/models/transport_route.dart';
import 'widgets/route_map.dart';
import 'widgets/submit_button.dart';
import 'widgets/transport_list_scaffold.dart';

/// The ordered stops of one route - add, edit and delete, like the
/// timetable's Manage Periods dialog. [canManage] is false for the
/// read-only roles, which still get to see the stops.
class ManageStopsDialog extends ConsumerWidget {
  const ManageStopsDialog({super.key, required this.routeId, required this.canManage});

  final int routeId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeState = ref.watch(routeDetailProvider(routeId));

    return AlertDialog(
      title: Text(routeState.value == null ? 'Stops' : 'Stops · ${routeState.value!.label}'),
      content: ConstrainedBox(
        // Wide enough for the map beside the list. Bounded in both
        // directions so the loading spinner does not stretch the dialog to
        // the viewport before the stops arrive.
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 940, maxHeight: 520),
        child: AsyncValueView<TransportRoute>(
          value: routeState,
          onRetry: () => ref.read(routeDetailProvider(routeId).notifier).refresh(),
          // Deliberately not empty when there are no stops: the map and the
          // invitation to add one are the whole point of opening this on a
          // route that has none.
          data: (context, route) => _StopsAndMap(routeId: routeId, route: route, canManage: canManage),
        ),
      ),
      actions: [
        if (canManage)
          TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => StopFormDialog(routeId: routeId, nextSequenceNumber: _nextSequence(routeState.value)),
            ),
            child: const Text('Add Stop'),
          ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }

  int _nextSequence(TransportRoute? route) {
    if (route == null || route.stops.isEmpty) return 1;
    return route.stops.map((s) => s.sequenceNumber).reduce((a, b) => a > b ? a : b) + 1;
  }
}

/// The stops down one side and the route on a map down the other.
///
/// Side by side where there is room, stacked where there is not - a phone
/// shows the map first, because the thing somebody opens this for on a
/// phone is usually to look at where the route goes.
class _StopsAndMap extends StatefulWidget {
  const _StopsAndMap({required this.routeId, required this.route, required this.canManage});

  final int routeId;
  final TransportRoute route;
  final bool canManage;

  @override
  State<_StopsAndMap> createState() => _StopsAndMapState();
}

class _StopsAndMapState extends State<_StopsAndMap> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final map = RouteMap(
      route: widget.route,
      selectedStopId: _selected,
      onSelectStop: (stop) => setState(() => _selected = stop.id),
    );

    final list = widget.route.stops.isEmpty
        ? const Padding(padding: EdgeInsets.all(16), child: Text('No stops on this route yet.'))
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stop in widget.route.stops)
                _StopRow(
                  routeId: widget.routeId,
                  stop: stop,
                  canManage: widget.canManage,
                  isSelected: stop.id == _selected,
                  onTap: () => setState(() => _selected = stop.id),
                ),
            ],
          );

    // Measured from the viewport, not a LayoutBuilder. An AlertDialog asks
    // its content how wide it would like to be, and a LayoutBuilder cannot
    // answer an intrinsic question - it would have to run its callback
    // speculatively against a tree it is not allowed to touch.
    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (!wide) {
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [map, const SizedBox(height: 12), list]),
      );
    }

    // A width, because an AlertDialog sizes itself to what its content says
    // it would like to be and a map says nothing at all - it fills whatever
    // room it is given. Left to the stop list alone the dialog came out
    // around 700 wide and the map got a sliver of it. The 112 is the
    // dialog's own padding and insets, so it never asks for more room than
    // the window has.
    final width = math.min(940.0, MediaQuery.sizeOf(context).width - 112);

    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SingleChildScrollView(child: list)),
          const SizedBox(width: 16),
          Expanded(child: SingleChildScrollView(child: map)),
        ],
      ),
    );
  }
}

class _StopRow extends ConsumerWidget {
  const _StopRow({
    required this.routeId,
    required this.stop,
    required this.canManage,
    this.isSelected = false,
    this.onTap,
  });

  final int routeId;
  final TransportStop stop;
  final bool canManage;

  /// Highlighted because its pin was tapped on the map, so the two halves
  /// of the dialog agree about which stop is being looked at.
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final times = [
      if (stop.pickupTime != null) 'Pickup ${stop.pickupTime}',
      if (stop.dropTime != null) 'Drop ${stop.dropTime}',
      '${stop.studentsCount} ${stop.studentsCount == 1 ? 'student' : 'students'}',
    ].join(' · ');

    return ListTile(
      dense: true,
      selected: isSelected,
      onTap: onTap,
      leading: CircleAvatar(radius: 14, child: Text('${stop.sequenceNumber}', style: const TextStyle(fontSize: 12))),
      title: Text(stop.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(times),
          _LocationIndicator(stop: stop),
        ],
      ),
      trailing: canManage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit stop',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) =>
                        StopFormDialog(routeId: routeId, stop: stop, nextSequenceNumber: stop.sequenceNumber),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete stop',
                  onPressed: () => confirmAndRun(
                    context,
                    title: 'Remove stop?',
                    message: 'This will remove "${stop.name}" from the route. This cannot be undone.',
                    successMessage: '${stop.name} was removed.',
                    action: () => ref.read(routeDetailProvider(routeId).notifier).deleteStop(stop),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

/// Add (no [stop]) or edit (with [stop]) one stop of a route.
class StopFormDialog extends ConsumerStatefulWidget {
  const StopFormDialog({super.key, required this.routeId, this.stop, required this.nextSequenceNumber});

  final int routeId;
  final TransportStop? stop;
  final int nextSequenceNumber;

  @override
  ConsumerState<StopFormDialog> createState() => _StopFormDialogState();
}

class _StopFormDialogState extends ConsumerState<StopFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.stop?.name ?? '');
  late final _sequenceController = TextEditingController(text: '${widget.nextSequenceNumber}');
  late TimeOfDay? _pickupTime = _parse(widget.stop?.pickupTime);
  late TimeOfDay? _dropTime = _parse(widget.stop?.dropTime);
  late final _latitudeController = TextEditingController(text: widget.stop?.latitude ?? '');
  late final _longitudeController = TextEditingController(text: widget.stop?.longitude ?? '');

  /// Which place in the school's list this call is at. Chosen when
  /// adding; fixed once the call exists, because moving a call to another
  /// place is removing one and adding another (docs/maps.md).
  int? _busStopId;

  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.stop != null;

  /// A call that came from the list does not own its name or its position.
  bool get _fromTheList => widget.stop?.isFromTheList ?? true;

  /// Where to look first, and what to bias address search towards. Null for
  /// a school nobody has placed, which simply means no bias.
  LatLng? _nearTheSchool(WidgetRef ref) {
    final route = ref.read(routeDetailProvider(widget.routeId)).value;
    final latitude = double.tryParse(route?.schoolLatitude ?? '');
    final longitude = double.tryParse(route?.schoolLongitude ?? '');

    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  static TimeOfDay? _parse(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String? _format(TimeOfDay? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sequenceController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isPickup}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isPickup ? _pickupTime : _dropTime) ?? const TimeOfDay(hour: 7, minute: 30),
    );
    if (picked == null) return;
    setState(() => isPickup ? _pickupTime = picked : _dropTime = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = const {};
    });

    try {
      final notifier = ref.read(routeDetailProvider(widget.routeId).notifier);
      final sequence = int.parse(_sequenceController.text.trim());

      if (_isEdit) {
        await notifier.editStop(
          widget.stop!,
          // The name and the position are the list's once the call came
          // from it; only a one-off still owns its own.
          name: _fromTheList ? null : _nameController.text.trim(),
          sequenceNumber: sequence,
          pickupTime: _format(_pickupTime),
          dropTime: _format(_dropTime),
          latitude: _fromTheList ? null : _latitudeController.text.trim(),
          longitude: _fromTheList ? null : _longitudeController.text.trim(),
        );
      } else {
        await notifier.addStop(
          busStopId: _busStopId!,
          sequenceNumber: sequence,
          pickupTime: _format(_pickupTime),
          dropTime: _format(_dropTime),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // A position problem is shown under the box it is about.
          final aboutPosition = _fieldErrors.containsKey('latitude') || _fieldErrors.containsKey('longitude');
          _errorMessage = aboutPosition ? null : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Stop' : 'Add Stop'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                // Which place in the school's list, when adding. A call
                // names a place; the name and the position belong there
                // (docs/maps.md).
                if (!_isEdit) ...[
                  _BusStopField(
                    routeId: widget.routeId,
                    selected: _busStopId,
                    error: _fieldErrors['bus_stop_id']?.first,
                    onChanged: (id) => setState(() => _busStopId = id),
                  ),
                  const SizedBox(height: 10),
                ] else if (_fromTheList) ...[
                  // Said rather than shown as an editable box: changing it
                  // here would fight the list, and the message says where
                  // the name actually lives.
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Stop',
                      helperText: 'From the school\'s bus stops. Rename it there and every route follows.',
                      helperMaxLines: 2,
                    ),
                    child: Text(widget.stop!.name),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Stop name',
                      helperText: 'A one-off, made before this school kept a list of stops.',
                      helperMaxLines: 2,
                    ),
                    maxLength: 100,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _sequenceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Order on route'),
                  validator: (v) {
                    final parsed = int.tryParse(v?.trim() ?? '');
                    return (parsed == null || parsed < 1) ? 'Enter a valid order (1 or more)' : null;
                  },
                ),
                const SizedBox(height: 10),
                _TimeField(
                  label: 'Pickup time (optional)',
                  value: _format(_pickupTime),
                  onTap: () => _pickTime(isPickup: true),
                  onClear: () => setState(() => _pickupTime = null),
                ),
                const SizedBox(height: 10),
                _TimeField(
                  label: 'Drop time (optional)',
                  value: _format(_dropTime),
                  onTap: () => _pickTime(isPickup: false),
                  onClear: () => setState(() => _dropTime = null),
                ),
                const SizedBox(height: 10),
                // Only a one-off still owns its own position. A call that
                // came from the list is moved by moving the bus stop.
                if (_isEdit && !_fromTheList)
                  LocationPicker(
                    latitude: _latitudeController,
                    longitude: _longitudeController,
                    // Biased towards the school, because "Station Road"
                    // means a different road in every city.
                    near: _nearTheSchool(ref),
                    origin: _nearTheSchool(ref),
                    child: CoordinatesFields(
                      latitude: _latitudeController,
                      longitude: _longitudeController,
                      latitudeError: _fieldErrors['latitude']?.first,
                      longitudeError: _fieldErrors['longitude']?.first,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        SubmitButton(isSubmitting: _isSubmitting, onPressed: _submit, label: 'Save'),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.value, required this.onTap, required this.onClear});

  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? null
              : IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: 'Clear $label', onPressed: onClear),
        ),
        child: Text(value ?? 'Not set'),
      ),
    );
  }
}

/// Whether the stop has been placed yet - a stop with no position cannot be
/// shown on a map or measured to from the bus.
class _LocationIndicator extends StatelessWidget {
  const _LocationIndicator({required this.stop});

  final TransportStop stop;

  @override
  Widget build(BuildContext context) {
    final color = stop.hasLocation ? context.appColors.success : Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stop.hasLocation ? Icons.place : Icons.location_off_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(stop.hasLocation ? 'Location set' : 'No location', style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

/// Which of the school's bus stops this call is at (docs/maps.md).
///
/// Only the ones this route does not already call at: a route passing one
/// corner twice is a mistake, and the server refuses it - offering it here
/// would be offering a refusal.
class _BusStopField extends ConsumerWidget {
  const _BusStopField({required this.routeId, required this.selected, required this.error, required this.onChanged});

  final int routeId;
  final int? selected;
  final String? error;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeDetailProvider(routeId)).value;
    final already = {for (final stop in route?.stops ?? const <TransportStop>[]) stop.busStopId};
    final places = ref.watch(busStopPickerProvider(route?.schoolId));

    return places.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text('Could not load the bus stops.', style: TextStyle(color: context.appColors.danger)),
      data: (all) {
        final offered = all.where((place) => !already.contains(place.id)).toList();

        if (offered.isEmpty) {
          return Text(
            all.isEmpty
                ? 'This school has no bus stops yet. Add them under Transport > Bus Stops, then build the route from them.'
                : 'This route already calls at every bus stop the school has.',
            style: TextStyle(color: context.appColors.muted),
          );
        }

        return DropdownButtonFormField<int>(
          key: const Key('bus-stop-field'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Bus stop',
            errorText: error,
            helperText: 'From the school\'s list. Add a new one under Transport > Bus Stops.',
            helperMaxLines: 2,
          ),
          items: [
            for (final place in offered)
              DropdownMenuItem(
                value: place.id,
                child: Text(place.name, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
          ],
          onChanged: onChanged,
          validator: (value) => value == null ? 'Pick a bus stop' : null,
        );
      },
    );
  }
}
