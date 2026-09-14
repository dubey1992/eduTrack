import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/currency_formatter.dart';
import '../application/payment_list_notifier.dart';
import '../data/models/payment.dart';
import '../../../core/utils/date_format.dart';

/// A read-only receipt view for one payment - the spec's "Payment Details"
/// / "Generate Receipt" screens, kept as a dialog rather than a full route
/// since it's just a formatted view of data the list screen already has.
///
/// The PDF that a school actually receives is rendered by the API and
/// emailed to its admins; this is where it can be sent again.
class PaymentReceiptDialog extends ConsumerStatefulWidget {
  const PaymentReceiptDialog({super.key, required this.payment});

  final Payment payment;

  @override
  ConsumerState<PaymentReceiptDialog> createState() => _PaymentReceiptDialogState();
}

class _PaymentReceiptDialogState extends ConsumerState<PaymentReceiptDialog> {
  bool _sending = false;

  Future<void> _sendReceipt() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(paymentListNotifierProvider.notifier).sendReceipt(widget.payment);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Receipt emailed to the school admins.')));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Payment Receipt'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatCurrency(payment.amount, payment.currencyCode),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              _Row('Receipt No.', 'RCPT-${payment.id.toString().padLeft(6, '0')}'),
              _Row('School', payment.schoolName ?? '-'),
              _Row('Payment Type', payment.paymentType.label),
              _Row('Payment Mode', payment.paymentMode.label),
              _Row('Payment Date', formatDate(payment.paymentDate)),
              _Row('Reference', payment.referenceNumber ?? '-'),
              _Row('Status', payment.status.label),
              _Row('Amount', formatCurrency(payment.amount, payment.currencyCode)),
              _Row('Received', formatCurrency(payment.paidAmount, payment.currencyCode)),
              _Row('Recorded By', payment.createdByName ?? '-'),
              if (payment.notes != null && payment.notes!.isNotEmpty) _Row('Notes', payment.notes!),
              // The figure someone opened this dialog to find out. Stated
              // rather than left as a subtraction between two rows above.
              if (payment.hasBalance) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'Balance due: ${formatCurrency(payment.remainingAmount, payment.currencyCode)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                payment.receiptSentAt == null
                    ? 'The receipt has not been emailed yet.'
                    : 'A receipt PDF has been emailed to this school\'s admins.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton.icon(
          onPressed: _sending ? null : _sendReceipt,
          icon: _sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.mail_outline, size: 18),
          label: Text(payment.receiptSentAt == null ? 'Email receipt' : 'Email again'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
