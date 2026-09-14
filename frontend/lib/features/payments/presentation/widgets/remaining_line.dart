import 'package:flutter/material.dart';

import '../../../../core/utils/currency_formatter.dart';

/// Spells out what is still owed on a part-payment, under the field where
/// the received amount is typed.
///
/// A form that shows "Amount 50,000" and "Received 20,000" is asking the
/// person to do the subtraction, and to do it again every time either figure
/// changes. This does it for them, live.
class RemainingLine extends StatelessWidget {
  const RemainingLine({super.key, required this.amount, required this.paidAmount, required this.currencyCode});

  final double? amount;
  final double? paidAmount;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final total = amount;
    final paid = paidAmount;

    // Nothing sensible to say until both figures are readable.
    if (total == null || total <= 0 || paid == null || paid < 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final remaining = total - paid;
    final settled = remaining <= 0;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: settled ? scheme.secondaryContainer : scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          settled
              ? 'Nothing remaining - this payment is fully settled.'
              : 'Remaining: ${formatCurrency(remaining, currencyCode)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: settled ? scheme.onSecondaryContainer : scheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
