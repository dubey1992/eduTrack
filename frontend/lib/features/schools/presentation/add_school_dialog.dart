import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../application/school_list_notifier.dart';
import 'widgets/coordinates_fields.dart';
import '../../early_access/data/models/early_access_request.dart';
import 'widgets/parent_school_field.dart';
import 'widgets/timezone_field.dart';

class AddSchoolDialog extends ConsumerStatefulWidget {
  const AddSchoolDialog({super.key, this.fromEarlyAccess});

  /// The signup request this school is being onboarded from, if any. Its
  /// details pre-fill the form, and creating the school marks the request
  /// Converted - see docs/early-access.md.
  final EarlyAccessRequest? fromEarlyAccess;

  @override
  ConsumerState<AddSchoolDialog> createState() => _AddSchoolDialogState();
}

class _AddSchoolDialogState extends ConsumerState<AddSchoolDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.fromEarlyAccess?.schoolName ?? '');
  final _registrationController = TextEditingController();
  late final _emailController = TextEditingController(text: widget.fromEarlyAccess?.email ?? '');
  // PhoneNumberField splits a '+91 9876543210' back into dial code and number, so seeding the whole
  // value is enough.
  late final _phoneController = TextEditingController(text: widget.fromEarlyAccess?.phone ?? '');
  final _addressController = TextEditingController();
  late final _cityController = TextEditingController(text: widget.fromEarlyAccess?.city ?? '');
  final _stateController = TextEditingController();
  late final _countryController = TextEditingController(text: widget.fromEarlyAccess?.country ?? '');
  final _postalCodeController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  String _currencyCode = Currency.common.first.code;
  // UTC until the Super Admin picks one, which matches what the column
  // defaults to for a school created any other way.
  String _timezone = 'UTC';
  int? _parentSchoolId;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _registrationController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(schoolPageNotifierProvider.notifier)
          .createSchool(
            name: _nameController.text.trim(),
            parentSchoolId: _parentSchoolId,
            earlyAccessRequestId: widget.fromEarlyAccess?.id,
            registrationNumber: _registrationController.text.trim().isEmpty
                ? null
                : _registrationController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            address: _addressController.text.trim(),
            city: _cityController.text.trim(),
            state: _stateController.text.trim(),
            country: _countryController.text.trim(),
            postalCode: _postalCodeController.text.trim(),
            currencyCode: _currencyCode,
            timezone: _timezone,
            latitude: _latitudeController.text.trim().isEmpty ? null : _latitudeController.text.trim(),
            longitude: _longitudeController.text.trim().isEmpty ? null : _longitudeController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('School created.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _required(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? '$label is required' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add School'),
      content: SizedBox(
        width: 480,
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
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'School name'),
                  validator: (v) => _required(v, 'School name'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _registrationController,
                  decoration: const InputDecoration(labelText: 'Registration number (optional)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 10),
                PhoneNumberField(controller: _phoneController, label: 'Phone', required: true),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) => _required(v, 'Address'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(labelText: 'City'),
                        validator: (v) => _required(v, 'City'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _stateController,
                        decoration: const InputDecoration(labelText: 'State'),
                        validator: (v) => _required(v, 'State'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _countryController,
                        decoration: const InputDecoration(labelText: 'Country'),
                        validator: (v) => _required(v, 'Country'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _postalCodeController,
                        decoration: const InputDecoration(labelText: 'Postal code'),
                        validator: (v) => _required(v, 'Postal code'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _currencyCode,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final currency in Currency.common)
                      DropdownMenuItem(value: currency.code, child: Text(currency.label)),
                  ],
                  onChanged: (value) => setState(() => _currencyCode = value!),
                ),
                const SizedBox(height: 10),
                TimezoneField(value: _timezone, onChanged: (value) => setState(() => _timezone = value)),
                const SizedBox(height: 12),
                ParentSchoolField(
                  value: _parentSchoolId,
                  onChanged: (value) => setState(() => _parentSchoolId = value),
                ),
                const SizedBox(height: 10),
                CoordinatesFields(latitude: _latitudeController, longitude: _longitudeController),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
