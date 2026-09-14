import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/school_clock_provider.dart';

import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/driver_page_notifier.dart';
import '../data/models/driver.dart';
import 'widgets/submit_button.dart';
import 'widgets/transport_school_picker.dart';
import '../../../core/utils/date_format.dart';

/// Add (no [driver]) or edit (with [driver]) a driver.
class DriverFormDialog extends ConsumerStatefulWidget {
  const DriverFormDialog({super.key, this.driver});

  final Driver? driver;

  @override
  ConsumerState<DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends ConsumerState<DriverFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.driver?.name ?? '');
  late final _mobileController = TextEditingController(text: widget.driver?.mobile ?? '');
  late final _licenceController = TextEditingController(text: widget.driver?.licenceNumber ?? '');
  late DateTime? _licenceExpiry = widget.driver?.licenceExpiry == null
      ? null
      : DateTime.parse(widget.driver!.licenceExpiry!);

  int? _schoolId;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEdit => widget.driver != null;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _licenceController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
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
    });

    try {
      final notifier = ref.read(driverPageNotifierProvider.notifier);
      final mobile = _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim();
      final expiry = _licenceExpiry == null ? null : DateFormat('yyyy-MM-dd').format(_licenceExpiry!);
      if (_isEdit) {
        await notifier.updateDriver(
          widget.driver!,
          name: _nameController.text.trim(),
          mobile: mobile,
          licenceNumber: _licenceController.text.trim(),
          licenceExpiry: expiry,
        );
      } else {
        await notifier.createDriver(
          schoolId: _schoolId,
          name: _nameController.text.trim(),
          mobile: mobile,
          licenceNumber: _licenceController.text.trim(),
          licenceExpiry: expiry,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_isEdit ? 'Driver updated.' : 'Driver added.')));
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
    final isSuperAdmin = ref.watch(authNotifierProvider).value?.role == UserRole.superAdmin;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Driver' : 'Add Driver'),
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
                if (isSuperAdmin && !_isEdit) ...[
                  TransportSchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Driver name'),
                  maxLength: 150,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                PhoneNumberField(controller: _mobileController, label: 'Mobile (optional)'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _licenceController,
                  decoration: const InputDecoration(labelText: 'Licence number'),
                  maxLength: 50,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Licence number is required' : null,
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickExpiry,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Licence expiry (optional)',
                      suffixIcon: _licenceExpiry == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear expiry',
                              onPressed: () => setState(() => _licenceExpiry = null),
                            ),
                    ),
                    child: Text(_licenceExpiry == null ? 'Not set' : formatDate(_licenceExpiry!)),
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
