import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/vehicle_page_notifier.dart';
import '../data/models/vehicle.dart';
import 'widgets/submit_button.dart';
import 'widgets/transport_school_picker.dart';

/// Add (no [vehicle]) or edit (with [vehicle]) a bus.
class VehicleFormDialog extends ConsumerStatefulWidget {
  const VehicleFormDialog({super.key, this.vehicle});

  final Vehicle? vehicle;

  @override
  ConsumerState<VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends ConsumerState<VehicleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.vehicle?.name ?? '');
  late final _registrationController = TextEditingController(text: widget.vehicle?.registrationNumber ?? '');
  late final _capacityController = TextEditingController(text: widget.vehicle?.capacity.toString() ?? '');

  int? _schoolId;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEdit => widget.vehicle != null;

  @override
  void dispose() {
    _nameController.dispose();
    _registrationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(vehiclePageNotifierProvider.notifier);
      final name = _nameController.text.trim();
      final registration = _registrationController.text.trim();
      final capacity = int.parse(_capacityController.text.trim());
      if (_isEdit) {
        await notifier.updateVehicle(widget.vehicle!, name: name, registrationNumber: registration, capacity: capacity);
      } else {
        await notifier.createVehicle(
          schoolId: _schoolId,
          name: name,
          registrationNumber: registration,
          capacity: capacity,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_isEdit ? 'Vehicle updated.' : 'Vehicle added.')));
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

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Vehicle' : 'Add Vehicle'),
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
                  TransportSchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Vehicle name', hintText: 'e.g. Bus 04'),
                  maxLength: 50,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _registrationController,
                  decoration: const InputDecoration(labelText: 'Registration number'),
                  maxLength: 30,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration number is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seating capacity'),
                  validator: (v) {
                    final parsed = int.tryParse(v?.trim() ?? '');
                    if (parsed == null || parsed < 1 || parsed > 200) return 'Enter a capacity between 1 and 200';
                    return null;
                  },
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
