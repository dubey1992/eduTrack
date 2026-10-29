import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/browser_timezone.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/dialog_message.dart';
import '../../../../core/widgets/phone_number_field.dart';
import '../../../demo_requests/data/demo_request_repository.dart';
import '../marketing_colors.dart';

/// The form behind every "Request a Demo" button (decided 2026-10-29).
///
/// Beside Join Early Access rather than instead of it: somebody asking for a
/// demo wants half an hour on a particular day, not an account. So it asks
/// who they are and when suits them - a day, and a part of the day in their
/// own timezone, which the browser supplies - and treats the rest as a
/// bonus.
///
/// Like the early access form it renders through the Navigator's overlay,
/// so the font is applied here rather than inherited.
Future<void> showDemoRequestDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const _DemoRequestDialog());
}

/// The parts of the day on offer, as the server names them.
const demoTimes = {'morning': 'Morning', 'afternoon': 'Afternoon', 'evening': 'Evening'};

class _DemoRequestDialog extends ConsumerStatefulWidget {
  const _DemoRequestDialog();

  @override
  ConsumerState<_DemoRequestDialog> createState() => _DemoRequestDialogState();
}

class _DemoRequestDialogState extends ConsumerState<_DemoRequestDialog> {
  /// A demo is booked within the next six months; the server says the same.
  static const _furthestDays = 180;

  final _formKey = GlobalKey<FormState>();
  final _contactName = TextEditingController();
  final _schoolName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _students = TextEditingController();
  final _message = TextEditingController();
  final _dateField = TextEditingController();

  DateTime? _preferredDate;
  String? _preferredTime;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _thankYou;

  @override
  void dispose() {
    for (final controller in [
      _contactName,
      _schoolName,
      _email,
      _phone,
      _city,
      _country,
      _students,
      _message,
      _dateField,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? '$label is required' : null;

  String? _optional(TextEditingController controller) => controller.text.trim().isEmpty ? null : controller.text.trim();

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: _furthestDays)),
      initialDate: _preferredDate ?? today.add(const Duration(days: 1)),
      helpText: 'Preferred day for the demo',
    );

    if (picked != null) {
      setState(() {
        _preferredDate = picked;
        _dateField.text = formatDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final message = await ref.read(demoRequestRepositoryProvider).submit({
        'contact_name': _contactName.text.trim(),
        'school_name': _schoolName.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'city': _optional(_city),
        'country': _country.text.trim(),
        'expected_students': _students.text.trim().isEmpty ? null : int.tryParse(_students.text.trim()),
        'preferred_date': DateFormat('yyyy-MM-dd').format(_preferredDate!),
        'preferred_time': _preferredTime,
        'timezone': browserTimezone(),
        'message': _optional(_message),
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
        title: Text('Demo requested', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        content: DialogMessage(thankYou, style: GoogleFonts.poppins()),
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
      title: Text('Request a Demo', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
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
                    'Tell us when suits you and we will confirm a time for a live walkthrough.',
                    style: GoogleFonts.poppins(color: MarketingColors.muted),
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Text(_errorMessage!, style: GoogleFonts.poppins(color: MarketingColors.danger)),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          controller: _schoolName,
                          decoration: const InputDecoration(labelText: 'School name'),
                          validator: (v) => _required(v, 'School name'),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _city,
                          decoration: const InputDecoration(labelText: 'City (optional)'),
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
                    decoration: const InputDecoration(labelText: 'Roughly how many students? (optional)'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final count = int.tryParse(v.trim());

                      return count == null || count < 1 ? 'Enter a number, or leave it empty' : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dateField,
                          readOnly: true,
                          onTap: _pickDate,
                          decoration: const InputDecoration(
                            labelText: 'Preferred day',
                            suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                          ),
                          validator: (_) => _preferredDate == null ? 'Pick a day for the demo' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _preferredTime,
                          decoration: const InputDecoration(labelText: 'Time of day (optional)'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Any time')),
                            for (final entry in demoTimes.entries)
                              DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value)),
                          ],
                          onChanged: (value) => setState(() => _preferredTime = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _message,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'What would you like to see? (optional)'),
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
              : Text('Request demo', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
