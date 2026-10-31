import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/school_clock_provider.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/decimal_input_formatter.dart';
import '../application/payment_list_notifier.dart';
import 'widgets/payment_services_field.dart';
import 'widgets/remaining_line.dart';
import '../data/models/payment.dart';
import '../../../core/utils/date_format.dart';

class EditPaymentDialog extends ConsumerStatefulWidget {
  const EditPaymentDialog({super.key, required this.payment});

  final Payment payment;

  @override
  ConsumerState<EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends ConsumerState<EditPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _services = PaymentServicesController(items: widget.payment.items);
  late final _paidAmountController = TextEditingController(text: widget.payment.paidAmount.toStringAsFixed(2));
  late final _referenceController = TextEditingController(text: widget.payment.referenceNumber ?? '');
  late final _notesController = TextEditingController(text: widget.payment.notes ?? '');

  late PaymentMode _paymentMode = widget.payment.paymentMode;
  late PaymentStatus _status = widget.payment.status;
  late DateTime _paymentDate = widget.payment.paymentDate;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _services.dispose();
    _paidAmountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double? get _enteredAmount => _services.total > 0 ? _services.total : null;

  /// Only sent for a part-payment - for every other status the API derives
  /// it from the status, which keeps the two from contradicting each other.
  double? get _paidAmount => _status == PaymentStatus.partial ? double.tryParse(_paidAmountController.text) : null;

  String? _validatePaidAmount(String? value) {
    final paid = double.tryParse(value ?? '');
    if (paid == null || paid <= 0) return 'Enter how much has been received';

    final total = _enteredAmount;
    if (total != null && paid > total) return 'This is more than the payment amount';
    if (total != null && paid == total) return 'Received in full - choose Paid instead';

    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: ref.read(schoolClockProvider).today,
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(paymentListNotifierProvider.notifier)
          .updatePayment(
            widget.payment,
            items: _services.items,
            paidAmount: _paidAmount,
            paymentDate: _paymentDate,
            paymentMode: _paymentMode,
            referenceNumber: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            status: _status,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment updated.')));
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
    return AlertDialog(
      title: Text('Edit Payment (${widget.payment.schoolName ?? 'School #${widget.payment.schoolId}'})'),
      content: SizedBox(
        width: 540,
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
                PaymentServicesField(controller: _services, currencyCode: widget.payment.currencyCode),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Payment date'),
                    child: Text(formatDate(_paymentDate)),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PaymentMode>(
                  initialValue: _paymentMode,
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                  items: [
                    for (final mode in PaymentMode.values) DropdownMenuItem(value: mode, child: Text(mode.label)),
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
                // Only a part-payment needs a second figure; for the others
                // the status already says what was received.
                if (_status == PaymentStatus.partial) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _paidAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalTextInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Amount received',
                      helperText: 'How much has arrived so far.',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: _validatePaidAmount,
                  ),
                  ListenableBuilder(
                    listenable: _services,
                    builder: (context, _) => RemainingLine(
                      amount: _enteredAmount,
                      paidAmount: _paidAmount,
                      currencyCode: widget.payment.currencyCode,
                    ),
                  ),
                ],
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
              : const Text('Save'),
        ),
      ],
    );
  }
}
