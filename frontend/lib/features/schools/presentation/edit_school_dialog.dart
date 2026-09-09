import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../application/school_list_notifier.dart';
import '../data/models/school.dart';

class EditSchoolDialog extends ConsumerStatefulWidget {
  const EditSchoolDialog({super.key, required this.school});

  final School school;

  @override
  ConsumerState<EditSchoolDialog> createState() => _EditSchoolDialogState();
}

class _EditSchoolDialogState extends ConsumerState<EditSchoolDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.school.name);
  late final _registrationController = TextEditingController(text: widget.school.registrationNumber ?? '');
  late final _emailController = TextEditingController(text: widget.school.email);
  late final _phoneController = TextEditingController(text: widget.school.phone);
  late final _addressController = TextEditingController(text: widget.school.address);
  late final _cityController = TextEditingController(text: widget.school.city);
  late final _stateController = TextEditingController(text: widget.school.state);
  late final _countryController = TextEditingController(text: widget.school.country);
  late final _postalCodeController = TextEditingController(text: widget.school.postalCode);
  late String _currencyCode = widget.school.currencyCode;

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
          .updateSchool(
            widget.school,
            name: _nameController.text.trim(),
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
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('School updated.')));
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
      title: Text('Edit ${widget.school.name}'),
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
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final currency in Currency.common)
                      DropdownMenuItem(value: currency.code, child: Text(currency.label)),
                  ],
                  onChanged: (value) => setState(() => _currencyCode = value!),
                ),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}
