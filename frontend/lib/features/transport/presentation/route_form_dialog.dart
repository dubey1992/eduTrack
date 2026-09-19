import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/route_page_notifier.dart';
import '../application/transport_pickers.dart';
import '../data/models/transport_route.dart';
import 'widgets/submit_button.dart';
import 'widgets/transport_school_picker.dart';

/// Add (no [route]) or edit (with [route]) a route: its name plus the
/// vehicle, driver and Bus Attendant currently serving it. Only active,
/// unassigned vehicles/drivers are offered - except the route's own, which
/// stays selectable even if it has since been deactivated. An attendant may
/// cover several routes, so every active one is offered.
class RouteFormDialog extends ConsumerStatefulWidget {
  const RouteFormDialog({super.key, this.route});

  final TransportRoute? route;

  @override
  ConsumerState<RouteFormDialog> createState() => _RouteFormDialogState();
}

class _RouteFormDialogState extends ConsumerState<RouteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.route?.name ?? '');

  int? _schoolId;
  late int? _vehicleId = widget.route?.vehicleId;
  late int? _driverId = widget.route?.driverId;
  late int? _attendantUserId = widget.route?.attendantUserId;

  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.route != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = const {};
    });

    try {
      final notifier = ref.read(routePageNotifierProvider.notifier);
      if (_isEdit) {
        await notifier.updateRoute(
          widget.route!,
          name: _nameController.text.trim(),
          vehicleId: _vehicleId,
          driverId: _driverId,
          attendantUserId: _attendantUserId,
        );
      } else {
        await notifier.createRoute(
          schoolId: _schoolId,
          name: _nameController.text.trim(),
          vehicleId: _vehicleId,
          driverId: _driverId,
          attendantUserId: _attendantUserId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_isEdit ? 'Route updated.' : 'Route added.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // The attendant's own message is shown under the attendant picker.
          _errorMessage = _fieldErrors.containsKey('attendant_user_id') ? null : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;
    final pickerSchoolId = _isEdit ? (picksSchool ? widget.route!.schoolId : null) : _schoolId;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Route' : 'Add Route'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                if (picksSchool && !_isEdit) ...[
                  TransportSchoolPicker(
                    selected: _schoolId,
                    onChanged: (value) => setState(() {
                      _schoolId = value;
                      _vehicleId = null;
                      _driverId = null;
                      _attendantUserId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Route name', hintText: 'e.g. Green Park'),
                  maxLength: 100,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                _VehiclePicker(
                  schoolId: pickerSchoolId,
                  selected: _vehicleId,
                  current: widget.route,
                  onChanged: (value) => setState(() => _vehicleId = value),
                ),
                const SizedBox(height: 10),
                _DriverPicker(
                  schoolId: pickerSchoolId,
                  selected: _driverId,
                  current: widget.route,
                  onChanged: (value) => setState(() => _driverId = value),
                ),
                const SizedBox(height: 10),
                _AttendantPicker(
                  schoolId: pickerSchoolId,
                  selected: _attendantUserId,
                  current: widget.route,
                  errorText: _fieldErrors['attendant_user_id']?.first,
                  onChanged: (value) => setState(() => _attendantUserId = value),
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

class _VehiclePicker extends ConsumerWidget {
  const _VehiclePicker({
    required this.schoolId,
    required this.selected,
    required this.current,
    required this.onChanged,
  });

  final int? schoolId;
  final int? selected;
  final TransportRoute? current;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesState = ref.watch(vehiclePickerProvider(schoolId));
    final vehicles = vehiclesState.value ?? const [];
    // Free vehicles, plus the one this route already has (which the API
    // reports as taken by this very route).
    final options = <int, String>{
      for (final v in vehicles)
        if (v.routeId == null || v.routeId == current?.id) v.id: '${v.name} · ${v.capacity} seats',
    };
    if (current?.vehicleId != null && !options.containsKey(current!.vehicleId)) {
      options[current!.vehicleId!] = '${current!.vehicleName} (inactive)';
    }

    // A menu opened while the list is still loading would never fill in -
    // keep it closed until the options are known.
    return DropdownButtonFormField<int?>(
      key: ValueKey('vehicle-${vehicles.length}'),
      initialValue: options.containsKey(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Vehicle',
        helperText: vehiclesState.isLoading ? 'Loading vehicles…' : null,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('No vehicle yet')),
        for (final entry in options.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: vehiclesState.isLoading ? null : onChanged,
    );
  }
}

class _DriverPicker extends ConsumerWidget {
  const _DriverPicker({required this.schoolId, required this.selected, required this.current, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final TransportRoute? current;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driversState = ref.watch(driverPickerProvider(schoolId));
    final drivers = driversState.value ?? const [];
    final options = <int, String>{
      for (final d in drivers)
        if (d.routeId == null || d.routeId == current?.id) d.id: d.name,
    };
    if (current?.driverId != null && !options.containsKey(current!.driverId)) {
      options[current!.driverId!] = '${current!.driverName} (inactive)';
    }

    return DropdownButtonFormField<int?>(
      key: ValueKey('driver-${drivers.length}'),
      initialValue: options.containsKey(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Driver', helperText: driversState.isLoading ? 'Loading drivers…' : null),
      items: [
        const DropdownMenuItem(value: null, child: Text('No driver yet')),
        for (final entry in options.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: driversState.isLoading ? null : onChanged,
    );
  }
}

/// The Bus Attendant who runs this route's trips on the bus. Keyed by user
/// id, which is what the route stores - not the staff profile id.
class _AttendantPicker extends ConsumerWidget {
  const _AttendantPicker({
    required this.schoolId,
    required this.selected,
    required this.current,
    required this.errorText,
    required this.onChanged,
  });

  final int? schoolId;
  final int? selected;
  final TransportRoute? current;
  final String? errorText;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendantsState = ref.watch(attendantPickerProvider(schoolId));
    final attendants = attendantsState.value ?? const [];
    final options = <int, String>{
      for (final a in attendants) a.userId: a.mobile == null ? a.name : '${a.name} · ${a.mobile}',
    };
    // The route's own attendant stays selectable after being switched off
    // (or when the list could not be read), so saving the route for another
    // reason does not quietly unassign them.
    if (current?.attendantUserId != null && !options.containsKey(current!.attendantUserId)) {
      final name = current!.attendantName ?? 'Current attendant';
      options[current!.attendantUserId!] = attendantsState.hasValue ? '$name (inactive)' : name;
    }

    String? helperText;
    if (attendantsState.isLoading) {
      helperText = 'Loading attendants…';
    } else if (attendantsState.hasError) {
      helperText = 'Could not load the attendants. Close and try again.';
    } else if (attendants.isEmpty) {
      helperText = 'No Bus Attendants yet - add one in Teachers & Staff.';
    }

    return DropdownButtonFormField<int?>(
      key: ValueKey('attendant-${attendants.length}'),
      initialValue: options.containsKey(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Bus attendant', helperText: helperText, errorText: errorText),
      items: [
        const DropdownMenuItem(value: null, child: Text('No attendant')),
        for (final entry in options.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: attendantsState.hasValue ? onChanged : null,
    );
  }
}
