import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/date_format.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../payments/data/models/payment.dart';

/// When and how pay left the school - for one payslip, or every unpaid one on
/// a run. The date defaults to today at the school and cannot be later.
///
/// [onPay] does the saving; the dialog closes with `true` once it succeeds and
/// stays open with the server's message when it does not.
class PayDialog extends ConsumerStatefulWidget {
  const PayDialog({super.key, required this.title, required this.confirmLabel, required this.onPay});

  final String title;
  final String confirmLabel;
  final Future<void> Function(DateTime paidOn, PaymentMode mode, String? reference) onPay;

  @override
  ConsumerState<PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends ConsumerState<PayDialog> {
  final _reference = TextEditingController();
  late DateTime _paidOn = ref.read(schoolClockProvider).today;
  PaymentMode _mode = PaymentMode.bankTransfer;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(2020),
      lastDate: today,
    );

    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _submit() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final reference = _reference.text.trim();
      await widget.onPay(_paidOn, _mode, reference.isEmpty ? null : reference);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Paid on',
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(formatDate(_paidOn)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMode>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Payment mode'),
              items: [for (final mode in PaymentMode.values) DropdownMenuItem(value: mode, child: Text(mode.label))],
              onChanged: (mode) => setState(() => _mode = mode!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Reference (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
