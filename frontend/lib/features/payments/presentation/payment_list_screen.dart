import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/payment_list_notifier.dart';
import '../application/payment_summary_notifier.dart';
import '../data/models/payment.dart';
import 'add_payment_dialog.dart';
import 'payment_receipt_dialog.dart';

class PaymentListScreen extends ConsumerWidget {
  const PaymentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsState = ref.watch(paymentListNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Payments',
          actions: [
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const AddPaymentDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Payment'),
            ),
          ],
        ),
        const _SummaryRow(),
        const SizedBox(height: 8),
        Expanded(
          child: AsyncValueView<List<Payment>>(
            value: paymentsState,
            onRetry: () => ref.read(paymentListNotifierProvider.notifier).refresh(),
            isEmpty: (payments) => payments.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No payments recorded yet.')),
            data: (context, payments) {
              return ResponsiveBuilder(
                mobile: (context) => _PaymentListMobile(payments: payments),
                desktop: (context) => _PaymentListDesktop(payments: payments),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends ConsumerWidget {
  const _SummaryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(paymentSummaryNotifierProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AsyncValueView<PaymentSummary>(
        value: summaryState,
        data: (context, summary) {
          final cards = <Widget>[
            for (final total in summary.totalByCurrency)
              KpiCard(
                label: 'Total Collection (${total.currencyCode})',
                value: formatCurrency(total.total, total.currencyCode),
              ),
            for (final monthly in summary.monthlyByCurrency)
              KpiCard(
                label: 'This Month (${monthly.currencyCode})',
                value: formatCurrency(monthly.total, monthly.currencyCode),
              ),
            KpiCard(label: 'Pending Payments', value: '${summary.pendingCount}'),
          ];

          return Wrap(spacing: 10, runSpacing: 10, children: cards);
        },
      ),
    );
  }
}

class _PaymentListMobile extends StatelessWidget {
  const _PaymentListMobile({required this.payments});

  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: payments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final payment = payments[index];
        return Card(
          child: ListTile(
            title: Text(payment.schoolName ?? 'School #${payment.schoolId}'),
            subtitle: Text(
              '${payment.paymentType.label} · ${formatCurrency(payment.amount, payment.currencyCode)}\n'
              '${DateFormat.yMMMd().format(payment.paymentDate)}',
            ),
            isThreeLine: true,
            trailing: _PaymentStatusBadge(status: payment.status),
            onTap: () => showDialog(
              context: context,
              builder: (_) => PaymentReceiptDialog(payment: payment),
            ),
          ),
        );
      },
    );
  }
}

class _PaymentListDesktop extends StatelessWidget {
  const _PaymentListDesktop({required this.payments});

  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('School')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Amount')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Mode')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final payment in payments)
                DataRow(
                  cells: [
                    DataCell(Text(payment.schoolName ?? 'School #${payment.schoolId}')),
                    DataCell(Text(payment.paymentType.label)),
                    DataCell(Text(formatCurrency(payment.amount, payment.currencyCode))),
                    DataCell(Text(DateFormat.yMMMd().format(payment.paymentDate))),
                    DataCell(Text(payment.paymentMode.label)),
                    DataCell(_PaymentStatusBadge(status: payment.status)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => PaymentReceiptDialog(payment: payment),
                            ),
                            child: const Text('Receipt'),
                          ),
                          _StatusMenu(payment: payment),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentStatusBadge extends StatelessWidget {
  const _PaymentStatusBadge({required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      PaymentStatus.paid => BadgeTone.success,
      PaymentStatus.pending => BadgeTone.warning,
      PaymentStatus.partial => BadgeTone.info,
      PaymentStatus.cancelled => BadgeTone.neutral,
    };

    return StatusBadge(label: status.label, tone: tone);
  }
}

class _StatusMenu extends ConsumerWidget {
  const _StatusMenu({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<PaymentStatus>(
      tooltip: 'Change status',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (status) => ref.read(paymentListNotifierProvider.notifier).updateStatus(payment, status),
      itemBuilder: (context) => [
        for (final status in PaymentStatus.values)
          PopupMenuItem(value: status, child: Text('Mark as ${status.label}')),
      ],
    );
  }
}
