import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/phone_number_field.dart';
import '../../../early_access/data/early_access_repository.dart';
import '../marketing_colors.dart';

/// The form behind every "Join Early Access" button.
///
/// It is the one thing in the app a complete stranger fills in, so it asks
/// for the least that makes a callback possible and treats everything else as
/// a bonus: a school that does not yet know its student count should still be
/// able to get in touch.
///
/// Dialogs render through the Navigator's overlay rather than inside
/// MarketingScreen, so they do not inherit its DefaultTextStyle - the Inter
/// font is applied explicitly here.
Future<void> showEarlyAccessDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const _EarlyAccessDialog());
}

class _EarlyAccessDialog extends ConsumerStatefulWidget {
  const _EarlyAccessDialog();

  @override
  ConsumerState<_EarlyAccessDialog> createState() => _EarlyAccessDialogState();
}

class _EarlyAccessDialogState extends ConsumerState<_EarlyAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _schoolName = TextEditingController();
  final _contactName = TextEditingController();
  final _contactRole = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _students = TextEditingController();
  final _currentSoftware = TextEditingController();
  final _message = TextEditingController();
  final _phone = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _thankYou;

  @override
  void dispose() {
    for (final controller in [
      _schoolName,
      _contactName,
      _contactRole,
      _email,
      _city,
      _country,
      _students,
      _currentSoftware,
      _message,
      _phone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? '$label is required' : null;

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final message = await ref.read(earlyAccessRepositoryProvider).submit({
        'school_name': _schoolName.text.trim(),
        'contact_name': _contactName.text.trim(),
        'contact_role': _contactRole.text.trim().isEmpty ? null : _contactRole.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'city': _city.text.trim(),
        'country': _country.text.trim(),
        'expected_students': _students.text.trim().isEmpty ? null : int.tryParse(_students.text.trim()),
        'current_software': _currentSoftware.text.trim().isEmpty ? null : _currentSoftware.text.trim(),
        'message': _message.text.trim().isEmpty ? null : _message.text.trim(),
      });

      if (mounted) setState(() => _thankYou = message);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thankYou = _thankYou;

    if (thankYou != null) {
      return AlertDialog(
        title: Text('Thanks for your interest!', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        content: Text(thankYou, style: GoogleFonts.poppins()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: MarketingColors.primary),
            child: Text('Got it', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Join Early Access', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: DefaultTextStyle.merge(
            style: GoogleFonts.poppins(),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tell us about your school and we will be in touch.',
                    style: GoogleFonts.poppins(color: MarketingColors.muted),
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Text(_errorMessage!, style: GoogleFonts.poppins(color: MarketingColors.danger)),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _schoolName,
                    decoration: const InputDecoration(labelText: 'School name'),
                    validator: (v) => _required(v, 'School name'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _contactName,
                          decoration: const InputDecoration(labelText: 'Your name'),
                          validator: (v) => _required(v, 'Your name'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _contactRole,
                          decoration: const InputDecoration(labelText: 'Your role (optional)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) {
                      final missing = _required(v, 'Email');
                      if (missing != null) return missing;

                      return v!.contains('@') ? null : 'Enter a valid email address';
                    },
                  ),
                  const SizedBox(height: 10),
                  PhoneNumberField(controller: _phone, label: 'Phone number', required: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _city,
                          decoration: const InputDecoration(labelText: 'City'),
                          validator: (v) => _required(v, 'City'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _country,
                          decoration: const InputDecoration(labelText: 'Country'),
                          validator: (v) => _required(v, 'Country'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _students,
                    keyboardType: TextInputType.number,
                    // Optional on purpose: plenty of schools do not know, and
                    // demanding a number loses the enquiry.
                    decoration: const InputDecoration(
                      labelText: 'Roughly how many students? (optional)',
                      helperText: 'A rough number is fine.',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final count = int.tryParse(v.trim());

                      return count == null || count < 1 ? 'Enter a number, or leave it empty' : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _currentSoftware,
                    decoration: const InputDecoration(labelText: 'What do you use today? (optional)'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _message,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Anything else? (optional)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: GoogleFonts.poppins()),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: MarketingColors.primary),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Request access', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
