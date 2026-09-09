import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../data/models/payment.dart';

/// A read-only receipt view for one payment - the spec's "Payment Details"
/// / "Generate Receipt" screens, kept as a dialog rather than a full route
/// since it's just a formatted view of data the list screen already has.
class PaymentReceiptDialog extends StatelessWidget {
  const PaymentReceiptDialog({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
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
              _Row('Receipt No.', 'PMT-${payment.id.toString().padLeft(6, '0')}'),
              _Row('School', payment.schoolName ?? '-'),
              _Row('Payment Type', payment.paymentType.label),
              _Row('Payment Mode', payment.paymentMode.label),
              _Row('Payment Date', DateFormat.yMMMd().format(payment.paymentDate)),
              _Row('Reference', payment.referenceNumber ?? '-'),
              _Row('Status', payment.status.label),
              _Row('Recorded By', payment.createdByName ?? '-'),
              if (payment.notes != null && payment.notes!.isNotEmpty) _Row('Notes', payment.notes!),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
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
