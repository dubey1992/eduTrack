import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/password_field.dart';
import '../../maps/presentation/location_picker.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../application/school_list_notifier.dart';
import '../data/models/working_week.dart';
import 'widgets/coordinates_fields.dart';
import '../../early_access/data/models/early_access_request.dart';
import 'widgets/parent_school_field.dart';
import 'widgets/timezone_field.dart';
import 'widgets/working_days_field.dart';

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
  // The week the product assumed everywhere until schools outside it
  // arrived; a new school keeps it unless somebody says otherwise.
  WorkingWeek _workingDays = WorkingWeek.mondayToFriday();
  int? _parentSchoolId;

  // The school's first School Admin, created in the same save so a new
  // school is never left with nobody who can sign in to it. On unless
  // the Super Admin switches it off.
  bool _createAdmin = true;
  late final _adminFirstNameController = TextEditingController(text: _firstWord(widget.fromEarlyAccess?.contactName));
  late final _adminLastNameController = TextEditingController(text: _rest(widget.fromEarlyAccess?.contactName));
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  static String _firstWord(String? name) => (name ?? '').trim().split(RegExp(r'\s+')).first;

  static String _rest(String? name) {
    final words = (name ?? '').trim().split(RegExp(r'\s+'));
    return words.length > 1 ? words.sublist(1).join(' ') : '';
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  /// Where the set-password email goes: the admin's own address, or the
  /// school's when none was typed.
  String get _adminEmail =>
      _adminEmailController.text.trim().isEmpty ? _emailController.text.trim() : _adminEmailController.text.trim();

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
    _adminFirstNameController.dispose();
    _adminLastNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
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
            workingDays: _workingDays,
            latitude: _latitudeController.text.trim().isEmpty ? null : _latitudeController.text.trim(),
            longitude: _longitudeController.text.trim().isEmpty ? null : _longitudeController.text.trim(),
            adminFirstName: _createAdmin ? _adminFirstNameController.text.trim() : null,
            adminLastName: _createAdmin ? _adminLastNameController.text.trim() : null,
            adminEmail: _createAdmin && _adminEmailController.text.trim().isNotEmpty
                ? _adminEmailController.text.trim()
                : null,
            adminPassword: _createAdmin && _adminPasswordController.text.isNotEmpty
                ? _adminPasswordController.text
                : null,
          );
      if (mounted) {
        final message = !_createAdmin
            ? 'School created.'
            : _adminPasswordController.text.isEmpty
            ? 'School and School Admin created. A link to set their password was emailed to $_adminEmail.'
            : 'School and School Admin created.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          final shownByField = _fieldErrors.keys.any((field) => field.startsWith('admin_'));
          _errorMessage = shownByField ? 'Check the School Admin details below.' : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _adminSection(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        SwitchListTile(
          key: const Key('school-create-admin'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Create the School Admin now'),
          subtitle: Text(
            'The person who runs this school in the app. They are emailed to set a password.',
            style: muted,
          ),
          value: _createAdmin,
          onChanged: (value) => setState(() => _createAdmin = value),
        ),
        if (_createAdmin) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('school-admin-first-name'),
                  controller: _adminFirstNameController,
                  decoration: InputDecoration(
                    labelText: 'Admin first name',
                    errorText: _serverError('admin_first_name'),
                  ),
                  validator: (v) => _required(v, 'First name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: const Key('school-admin-last-name'),
                  controller: _adminLastNameController,
                  decoration: InputDecoration(labelText: 'Admin last name', errorText: _serverError('admin_last_name')),
                  validator: (v) => _required(v, 'Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('school-admin-email'),
            controller: _adminEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Admin email (optional)',
              helperText: 'Leave blank to use the school email.',
              errorText: _serverError('admin_email'),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              return value.isEmpty || value.contains('@') ? null : 'Enter a valid email';
            },
          ),
          const SizedBox(height: 10),
          PasswordField(
            key: const Key('school-admin-password'),
            controller: _adminPasswordController,
            label: 'Admin password (optional)',
            helperText: optionalPasswordHint,
            validator: optionalPasswordProblem,
          ),
          if (_serverError('admin_password') != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                _serverError('admin_password')!,
                style: TextStyle(color: context.appColors.danger, fontSize: 12),
              ),
            ),
        ],
      ],
    );
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
                const SizedBox(height: 16),
                WorkingDaysField(value: _workingDays, onChanged: (value) => setState(() => _workingDays = value)),
                const SizedBox(height: 12),
                ParentSchoolField(
                  value: _parentSchoolId,
                  onChanged: (value) => setState(() => _parentSchoolId = value),
                ),
                const SizedBox(height: 10),
                // The map fills the boxes in; the boxes are still what the
                // form sends, and still work with no map at all.
                LocationPicker(
                  latitude: _latitudeController,
                  longitude: _longitudeController,
                  child: CoordinatesFields(latitude: _latitudeController, longitude: _longitudeController),
                ),
                const SizedBox(height: 16),
                _adminSection(context),
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
