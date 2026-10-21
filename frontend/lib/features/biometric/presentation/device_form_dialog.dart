import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../../transport/presentation/widgets/submit_button.dart';
import '../application/device_page_notifier.dart';
import '../data/models/biometric_device.dart';

/// Register (no [device]) or rename (with [device]) a fingerprint reader.
///
/// The serial number is the one field that matters: it is how the device
/// says who it is when it starts posting punches, so it has to be the one
/// printed on the box rather than a name somebody chose.
class DeviceFormDialog extends ConsumerStatefulWidget {
  const DeviceFormDialog({super.key, this.device});

  final BiometricDevice? device;

  @override
  ConsumerState<DeviceFormDialog> createState() => _DeviceFormDialogState();
}

class _DeviceFormDialogState extends ConsumerState<DeviceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.device?.name ?? '');
  late final _serialController = TextEditingController(text: widget.device?.serialNumber ?? '');
  late final _locationController = TextEditingController(text: widget.device?.location ?? '');

  /// Always starts empty, even when a key is already set: the server never
  /// sends it back, so there is nothing to prefill with and a dot-filled
  /// box would be a lie about what pressing Save does.
  final _pushKeyController = TextEditingController();

  int? _schoolId;
  bool _pushKeyTouched = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEdit => widget.device != null;

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _pushKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(devicePageNotifierProvider.notifier);
      final name = _nameController.text.trim();
      final serial = _serialController.text.trim();
      final location = _locationController.text.trim();
      // Untouched means "leave it as it is"; the server is only told about
      // the key when somebody typed in that box.
      final pushKey = _pushKeyTouched ? _pushKeyController.text.trim() : null;

      if (_isEdit) {
        await notifier.editDevice(
          widget.device!,
          name: name,
          serialNumber: serial,
          location: location,
          pushKey: pushKey,
        );
      } else {
        await notifier.createDevice(
          schoolId: _schoolId,
          name: name,
          serialNumber: serial,
          location: location,
          pushKey: pushKey,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_isEdit ? 'Device updated.' : 'Device registered.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      // The server refuses a serial another school already has, and says so
      // without naming that school. Shown as it came rather than replaced.
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Device' : 'Register Device'),
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
                  SchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Device name', hintText: 'e.g. Front gate'),
                  maxLength: 100,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _serialController,
                  decoration: const InputDecoration(
                    labelText: 'Serial number',
                    helperText: 'Printed on the device. It is how the device identifies itself.',
                  ),
                  maxLength: 64,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Serial number is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    helperText: 'Optional. Where in the school it is, so somebody can go and find it.',
                  ),
                  maxLength: 100,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _pushKeyController,
                  decoration: InputDecoration(
                    labelText: 'Push key',
                    helperText: widget.device?.hasPushKey ?? false
                        ? 'A key is set. Type a new one to replace it, or empty this box to remove it. '
                              'Leave it alone to keep the one it has.'
                        : 'Optional. A secret the device sends with its punches, where it can. '
                              'Set the same value on the device.',
                    helperMaxLines: 3,
                  ),
                  maxLength: 64,
                  onChanged: (_) => _pushKeyTouched = true,
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
