import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../../maps/presentation/location_picker.dart';
import '../application/bus_stop_page_notifier.dart';
import '../data/models/bus_stop.dart';
import 'widgets/submit_button.dart';

/// Adding a place to the school's list of bus stops, or changing one
/// (docs/maps.md).
///
/// The position is required and the form says so by having no way to leave
/// it out: either somebody tapped the map to get here, or they pick on the
/// picker below. A stop nobody can point to is not a stop.
class BusStopFormDialog extends ConsumerStatefulWidget {
  const BusStopFormDialog({super.key, this.stop, this.schoolId, this.at, this.returnsTheStop = false});

  /// The stop being changed, or null to add one.
  final BusStop? stop;

  /// Which school a new stop belongs to, when the screen is filtered to one.
  final int? schoolId;

  /// Where somebody tapped on the map, for a new stop. The picker opens
  /// there with the boxes already filled.
  final LatLng? at;

  /// Pop the stop that was made rather than nothing. The route builder
  /// needs it: it has just created a place and is about to put it on the
  /// route in the same action (docs/maps.md).
  final bool returnsTheStop;

  @override
  ConsumerState<BusStopFormDialog> createState() => _BusStopFormDialogState();
}

class _BusStopFormDialogState extends ConsumerState<BusStopFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.stop?.name ?? '');
  late final _landmarkController = TextEditingController(text: widget.stop?.landmark ?? '');
  late final _latitudeController = TextEditingController(
    text: widget.stop?.latitude ?? widget.at?.latitude.toStringAsFixed(7) ?? '',
  );
  late final _longitudeController = TextEditingController(
    text: widget.stop?.longitude ?? widget.at?.longitude.toStringAsFixed(7) ?? '',
  );

  int? _schoolId;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.stop != null;

  @override
  void initState() {
    super.initState();
    _schoolId = widget.schoolId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _landmarkController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  /// What to call the school in the distance line, and where it is.
  ///
  /// Both read off the page the list came on rather than from the schools
  /// list: a Transport Manager answers for their own school without being
  /// able to read /schools at all.
  String? _schoolName() => ref.read(busStopPageNotifierProvider.notifier).schoolName;

  LatLng? _nearTheSchool() => ref.read(busStopPageNotifierProvider.notifier).schoolAt;

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = const {};
    });

    try {
      final notifier = ref.read(busStopPageNotifierProvider.notifier);
      final name = _nameController.text.trim();
      final landmark = _landmarkController.text.trim();
      final latitude = _latitudeController.text.trim();
      final longitude = _longitudeController.text.trim();

      BusStop? made;

      if (_isEdit) {
        await notifier.editStop(widget.stop!, name: name, latitude: latitude, longitude: longitude, landmark: landmark);
      } else {
        made = await notifier.addStop(
          schoolId: _schoolId,
          name: name,
          latitude: latitude,
          longitude: longitude,
          landmark: landmark.isEmpty ? null : landmark,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEdit ? '$name saved.' : '$name added.')));
        // The route builder asked for what was made: it is putting this
        // place on the route in the same action (docs/maps.md).
        Navigator.of(context).pop(widget.returnsTheStop ? made : null);
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());

      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // A position problem is shown under the boxes it is about.
          final aboutPosition = _fieldErrors.containsKey('latitude') || _fieldErrors.containsKey('longitude');
          _errorMessage = aboutPosition ? null : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _errorFor(String field) => _fieldErrors[field]?.first;

  @override
  Widget build(BuildContext context) {
    final picksSchool = !_isEdit && (ref.watch(authNotifierProvider).value?.picksSchool ?? false);

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Bus Stop' : 'Add Bus Stop'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                // Said before the change, not after: renaming or moving a
                // place reaches every route that calls at it, which is the
                // point of keeping a list and also a surprise if nobody
                // mentioned it (docs/maps.md, S3).
                if (_isEdit && widget.stop!.isOnARoute) ...[
                  Row(
                    children: [
                      Icon(Icons.alt_route_outlined, size: 16, color: context.appColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.stop!.routesCount == 1
                              ? 'On 1 route. Renaming it or moving the pin changes that route too.'
                              : 'On ${widget.stop!.routesCount} routes. Renaming it or moving the pin '
                                    'changes all of them.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.appColors.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (picksSchool) ...[
                  SchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Stop name',
                    hintText: 'e.g. Market Square',
                    errorText: _errorFor('name'),
                    helperText: 'How people refer to it. Every stop at this school needs its own name.',
                  ),
                  maxLength: 100,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _landmarkController,
                  decoration: InputDecoration(
                    labelText: 'Landmark',
                    errorText: _errorFor('landmark'),
                    helperText: 'Optional. What you would tell a parent on the phone.',
                  ),
                  maxLength: 100,
                ),
                const SizedBox(height: 10),
                LocationPicker(
                  latitude: _latitudeController,
                  longitude: _longitudeController,
                  near: _nearTheSchool(),
                  // The school, pinned in its own colour and measured
                  // against: a stop is only ever placed relative to it,
                  // and the wrong city is what this catches.
                  origin: _nearTheSchool(),
                  originLabel: _schoolName(),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitudeController,
                          decoration: InputDecoration(labelText: 'Latitude', errorText: _errorFor('latitude')),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Pick where it is' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _longitudeController,
                          decoration: InputDecoration(labelText: 'Longitude', errorText: _errorFor('longitude')),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Pick where it is' : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (_isEdit) _RetireButton(stop: widget.stop!),
        SubmitButton(isSubmitting: _isSubmitting, onPressed: _submit, label: 'Save'),
      ],
    );
  }
}

/// Retiring a stop rather than removing it: the one a route still calls at
/// cannot be deleted, and often should not be - it is simply not used any
/// more.
class _RetireButton extends ConsumerStatefulWidget {
  const _RetireButton({required this.stop});

  final BusStop stop;

  @override
  ConsumerState<_RetireButton> createState() => _RetireButtonState();
}

class _RetireButtonState extends ConsumerState<_RetireButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final goingInactive = widget.stop.isActive;

    return TextButton(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);

              try {
                await ref
                    .read(busStopPageNotifierProvider.notifier)
                    .editStop(widget.stop, status: goingInactive ? 'inactive' : 'active');

                if (!context.mounted) return;

                Navigator.of(context).pop();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: Text(goingInactive ? 'Make inactive' : 'Make active'),
    );
  }
}
