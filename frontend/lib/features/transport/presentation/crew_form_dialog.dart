import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/crew_list_notifier.dart';

/// Adds a driver or an attendant from Transport > Crew
/// (docs/driver-app.md, D10).
///
/// The short form of Add Employee: the person, how they sign in (their
/// mobile), the employee id the school knows them by, and for a driver the
/// licence. No email, no password, no department - a Transport Manager adding
/// the crew of a bus has none of those to give, and the server fills in what
/// a crew member's account needs. The School Admin's full form in Teachers &
/// Staff produces exactly the same records.
class CrewFormDialog extends ConsumerStatefulWidget {
  const CrewFormDialog({super.key});

  @override
  ConsumerState<CrewFormDialog> createState() => _CrewFormDialogState();
}

class _CrewFormDialogState extends ConsumerState<CrewFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _licenceController = TextEditingController();

  UserRole _role = UserRole.driver;
  int? _schoolId;
  DateTime? _licenceExpiry;
  late DateTime _joiningDate;

  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isDriver => _role == UserRole.driver;

  String? _serverError(String field) => _fieldErrors[field]?.first;

  @override
  void initState() {
    super.initState();
    _joiningDate = ref.read(schoolClockProvider).today;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _employeeIdController.dispose();
    _licenceController.dispose();
    super.dispose();
  }

  Future<void> _pickLicenceExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenceExpiry ?? ref.read(schoolClockProvider).today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _licenceExpiry = picked);
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
          .read(crewListNotifierProvider.notifier)
          .addCrew(
            role: _role,
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            mobile: _mobileController.text.trim(),
            employeeId: _employeeIdController.text.trim(),
            schoolId: _schoolId,
            joiningDate: _joiningDate,
            licenceNumber: _isDriver ? _licenceController.text.trim() : null,
            licenceExpiry: _isDriver ? _licenceExpiry : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_role.label} added. Open their Sign-in to issue a setup code for their phone.')),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          final shownByField = _serverError('mobile') != null || _serverError('licence_number') != null;
          _errorMessage = shownByField ? null : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;
    final colors = context.appColors;

    return AlertDialog(
      title: const Text('Add bus crew'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: colors.danger)),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<UserRole>(
                  key: const Key('crew-role'),
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: UserRole.driver, child: Text('Driver')),
                    DropdownMenuItem(value: UserRole.busAttendant, child: Text('Attendant')),
                  ],
                  onChanged: (value) => setState(() => _role = value!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('crew-first-name'),
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'First name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: const Key('crew-last-name'),
                        controller: _lastNameController,
                        decoration: const InputDecoration(labelText: 'Last name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PhoneNumberField(controller: _mobileController, label: 'Mobile', required: true),
                if (_serverError('mobile') != null) _FieldError(_serverError('mobile')!),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('crew-employee-id'),
                  controller: _employeeIdController,
                  decoration: InputDecoration(labelText: 'Employee ID', errorText: _serverError('employee_id')),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_isDriver) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('crew-licence-number'),
                    controller: _licenceController,
                    decoration: InputDecoration(
                      labelText: 'Driving licence number',
                      errorText: _serverError('licence_number'),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required for a driver' : null,
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    key: const Key('crew-licence-expiry'),
                    onTap: _pickLicenceExpiry,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Licence expiry (optional)',
                        suffixIcon: _licenceExpiry == null
                            ? const Icon(Icons.calendar_today_outlined, size: 18)
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: 'Clear',
                                onPressed: () => setState(() => _licenceExpiry = null),
                              ),
                      ),
                      child: Text(_licenceExpiry == null ? 'Not set' : formatDate(_licenceExpiry!)),
                    ),
                  ),
                ],
                if (picksSchool) ...[
                  const SizedBox(height: 10),
                  SchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No password: a ${_role.label} signs in to the Driver app with this mobile number and a '
                        '4-digit passcode on a registered phone. After saving, open their Sign-in to issue a '
                        'setup code.',
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('crew-save'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(message, style: TextStyle(color: context.appColors.danger, fontSize: 12)),
      ),
    );
  }
}
