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
/// vehicle and driver currently serving it. Only active, unassigned
/// vehicles/drivers are offered - except the route's own, which stays
/// selectable even if it has since been deactivated.
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

  bool _isSubmitting = false;
  String? _errorMessage;

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
    });

    try {
      final notifier = ref.read(routePageNotifierProvider.notifier);
      if (_isEdit) {
        await notifier.updateRoute(
          widget.route!,
          name: _nameController.text.trim(),
          vehicleId: _vehicleId,
          driverId: _driverId,
        );
      } else {
        await notifier.createRoute(
          schoolId: _schoolId,
          name: _nameController.text.trim(),
          vehicleId: _vehicleId,
          driverId: _driverId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_isEdit ? 'Route updated.' : 'Route added.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.role.picksSchool ?? false;
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
