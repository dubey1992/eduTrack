import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../application/company_details_notifier.dart';
import '../data/models/company_details.dart';

/// School365ai's own business details, printed as the issuer on the receipt
/// a school gets for paying the platform. Super Admin only - the API refuses
/// everyone else, and the nav item is not shown to them.
class CompanyDetailsScreen extends ConsumerWidget {
  const CompanyDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyDetailsNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Company Details'),
        Expanded(
          child: AsyncValueView<CompanyDetails>(
            value: state,
            onRetry: () => ref.read(companyDetailsNotifierProvider.notifier).load(),
            data: (context, details) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _CompanyForm(details: details),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One field of the form: its API name, label, hint, limit, and whether it
/// is required.
class _Field {
  const _Field(this.key, this.label, {this.hint, this.max = 100, this.required = false, this.wide = false});

  final String key;
  final String label;
  final String? hint;
  final int max;
  final bool required;
  final bool wide;
}

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _website = RegExp(r'^(https?://)?[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/\S*)?$');

const _sections = <(String, List<_Field>)>[
  (
    'Business',
    [
      _Field('legal_name', 'Legal name', hint: 'e.g. School365 AI Private Limited', max: 150, required: true),
      _Field('trading_name', 'Trading name', hint: 'e.g. School365ai'),
      _Field('tax_number', 'Tax number', hint: 'GSTIN, VAT or sales-tax number', max: 30),
      _Field('registration_number', 'Company registration number', hint: 'CIN or equivalent', max: 30),
    ],
  ),
  (
    'Address',
    [
      _Field('address', 'Street address', max: 255, wide: true),
      _Field('city', 'City'),
      _Field('state', 'State'),
      _Field('postal_code', 'Postal code', max: 20),
      _Field('country', 'Country'),
    ],
  ),
  (
    'Contact',
    [
      _Field('phone', 'Phone', max: 30),
      _Field('email', 'Billing email', max: 150),
      _Field('website', 'Website', hint: 'e.g. school365ai.com', max: 150),
      _Field('logo_url', 'Logo address', hint: 'https://... a PNG or JPEG', max: 255),
    ],
  ),
];

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm({required this.details});

  final CompanyDetails details;

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final entry in widget.details.toFields().entries) entry.key: TextEditingController(text: entry.value ?? ''),
  };
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _check(_Field field, String? raw) {
    final value = (raw ?? '').trim();

    if (value.isEmpty) return field.required ? 'Enter the ${field.label.toLowerCase()}.' : null;
    if (field.key == 'email' && !_email.hasMatch(value)) return 'Enter a valid email address.';
    if (field.key == 'website' && !_website.hasMatch(value)) return 'Enter a web address, such as school365ai.com.';
    if (field.key == 'logo_url' && !value.toLowerCase().startsWith(RegExp('https?://'))) {
      return 'The logo must be an http(s) address of an image.';
    }

    return null;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(companyDetailsNotifierProvider.notifier).save({
        for (final entry in _controllers.entries) entry.key: entry.value.text.trim(),
      });
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Company details saved. New receipts will carry them.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _error = failure.message;
          _fieldErrors = failure.validationErrors;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Form(
      key: _formKey,
      autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Printed as the issuer on the receipt a school gets for paying School365ai. '
            'Until these are saved, receipts carry the name "School365ai" and nothing more.',
            style: TextStyle(color: colors.muted),
          ),
          if (widget.details.updatedByName != null) ...[
            const SizedBox(height: 4),
            Text('Last saved by ${widget.details.updatedByName}.', style: TextStyle(color: colors.muted, fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: TextStyle(color: colors.onDangerContainer)),
            ),
          ],
          for (final (title, fields) in _sections) ...[
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final field in fields)
                  SizedBox(
                    width: field.wide ? 576 : 280,
                    child: TextFormField(
                      controller: _controllers[field.key],
                      enabled: !_saving,
                      maxLength: field.max,
                      decoration: InputDecoration(
                        labelText: field.required ? '${field.label} *' : field.label,
                        hintText: field.hint,
                        counterText: '',
                        errorText: _fieldErrors[field.key]?.first,
                        errorMaxLines: 3,
                      ),
                      validator: (value) => _check(field, value),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save details'),
            ),
          ),
        ],
      ),
    );
  }
}
