import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../schools/data/models/school.dart';
import '../application/payment_list_notifier.dart';
import '../data/models/payment.dart';

class AddPaymentDialog extends ConsumerStatefulWidget {
  const AddPaymentDialog({super.key});

  @override
  ConsumerState<AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends ConsumerState<AddPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  int? _schoolId;
  PaymentType _paymentType = PaymentType.setupFee;
  PaymentMode _paymentMode = PaymentMode.bankTransfer;
  PaymentStatus _status = PaymentStatus.paid;
  DateTime _paymentDate = DateTime.now();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate() || _schoolId == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(paymentListNotifierProvider.notifier)
          .createPayment(
            schoolId: _schoolId!,
            paymentType: _paymentType,
            amount: double.parse(_amountController.text),
            paymentDate: _paymentDate,
            paymentMode: _paymentMode,
            referenceNumber: _referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            status: _status,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schoolsState = ref.watch(schoolListNotifierProvider);

    return AlertDialog(
      title: const Text('Add Payment'),
      content: SizedBox(
        width: 460,
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
                AsyncValueView<List<School>>(
                  value: schoolsState,
                  data: (context, schools) {
                    return DropdownButtonFormField<int>(
                      initialValue: _schoolId,
                      decoration: const InputDecoration(labelText: 'School'),
                      items: [
                        for (final school in schools)
                          DropdownMenuItem(
                            value: school.id,
                            child: Text('${school.name} (${school.currencyCode})'),
                          ),
                      ],
                      onChanged: (value) => setState(() => _schoolId = value),
                      validator: (v) => v == null ? 'School is required' : null,
                    );
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PaymentType>(
                  initialValue: _paymentType,
                  decoration: const InputDecoration(labelText: 'Payment type'),
                  items: [
                    for (final type in PaymentType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) => setState(() => _paymentType = value!),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  validator: (v) {
                    final parsed = double.tryParse(v ?? '');
                    if (parsed == null || parsed <= 0) return 'Enter a valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Payment date'),
                    child: Text(DateFormat.yMMMd().format(_paymentDate)),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PaymentMode>(
                  initialValue: _paymentMode,
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                  items: [
                    for (final mode in PaymentMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (value) => setState(() => _paymentMode = value!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PaymentStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final status in PaymentStatus.values)
                      DropdownMenuItem(value: status, child: Text(status.label)),
                  ],
                  onChanged: (value) => setState(() => _status = value!),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _referenceController,
                  decoration: const InputDecoration(labelText: 'Reference number (optional)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
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
              : const Text('Save Payment'),
        ),
      ],
    );
  }
}
