import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/decimal_input_formatter.dart';
import '../data/models/payroll.dart';

/// A one-off earning or deduction on one draft payslip: a named amount and
/// the reason for it. Never pro-rated - see docs/payroll.md.
class AdjustmentDialog extends StatefulWidget {
  const AdjustmentDialog({super.key, required this.onSave});

  final Future<void> Function(PayComponentType type, String name, String amount, String note) onSave;

  @override
  State<AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  PayComponentType _type = PayComponentType.earning;
  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await widget.onSave(_type, _name.text.trim(), _amount.text.trim(), _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() {
        _error = failure.message;
        _fieldErrors = failure.validationErrors;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Adjustment'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null && _fieldErrors.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              SegmentedButton<PayComponentType>(
                segments: [
                  for (final type in PayComponentType.values) ButtonSegment(value: type, label: Text(type.label)),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => setState(() => _type = selection.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: _type == PayComponentType.earning ? 'e.g. Exam duty' : 'e.g. Advance recovery',
                  errorText: _serverError('name'),
                ),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Name is required' : null,
              ),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [DecimalTextInputFormatter()],
                decoration: InputDecoration(labelText: 'Amount', errorText: _serverError('amount')),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  return amount == null || amount <= 0 ? 'Enter an amount above zero' : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                maxLength: 255,
                decoration: InputDecoration(labelText: 'Reason', errorText: _serverError('note')),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Say why - it goes on the payslip' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add Adjustment'),
        ),
      ],
    );
  }
}
