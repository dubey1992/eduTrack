import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/payment_list_notifier.dart';
import '../application/payment_summary_notifier.dart';
import '../data/models/payment.dart';
import 'add_payment_dialog.dart';
import 'edit_payment_dialog.dart';
import 'payment_receipt_dialog.dart';

class PaymentListScreen extends ConsumerStatefulWidget {
  const PaymentListScreen({super.key});

  @override
  ConsumerState<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends ConsumerState<PaymentListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
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
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(paymentListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        const _SummaryRow(),
        const SizedBox(height: 8),
        Expanded(
          child: AsyncValueView<PagedList<Payment>>(
            value: paymentsState,
            onRetry: () => ref.read(paymentListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No payments recorded yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _PaymentListMobile(payments: page.items),
                      desktop: (context) => _PaymentListDesktop(payments: page.items),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(paymentListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(paymentListNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PaymentStatusBadge(status: payment.status),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => EditPaymentDialog(payment: payment),
                  ),
                ),
              ],
            ),
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
                              builder: (_) => EditPaymentDialog(payment: payment),
                            ),
                            child: const Text('Edit'),
                          ),
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
      onSelected: (status) async {
        try {
          await ref.read(paymentListNotifierProvider.notifier).updateStatus(payment, status);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment marked as ${status.label}.')));
          }
        } catch (error) {
          if (context.mounted) {
            final failure = error is Failure ? error : Failure.unknown(error.toString());
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
          }
        }
      },
      itemBuilder: (context) => [
        for (final status in PaymentStatus.values) PopupMenuItem(value: status, child: Text('Mark as ${status.label}')),
      ],
    );
  }
}
