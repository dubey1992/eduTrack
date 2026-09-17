import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/payroll_notifiers.dart';
import '../data/models/payroll.dart';
import 'payslip_dialog.dart';

/// Every employee's own payslips, newest month first - only once a run is
/// finalized, since a draft can still change after it is read.
class MyPayslipsScreen extends ConsumerWidget {
  const MyPayslipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myPayslipsNotifierProvider);
    final notifier = ref.read(myPayslipsNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'My Payslips'),
        Expanded(
          child: AsyncValueView<PagedList<Payslip>>(
            value: state,
            onRetry: notifier.refresh,
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) =>
                const Center(child: Text('No payslips yet. They appear once payroll is finalized.')),
            data: (context, page) => Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final payslip = page.items[index];

                      return Card(
                        child: ListTile(
                          title: Text(payslip.periodLabel),
                          subtitle: Text(
                            'Net pay ${formatCurrency(double.parse(payslip.netPay), payslip.currencyCode)} · '
                            '${formatDays(payslip.paidDays)} of ${formatDays(payslip.workingDays)} days paid',
                          ),
                          trailing: StatusBadge(
                            label: payslip.status.label,
                            tone: payslip.isPaid ? BadgeTone.success : BadgeTone.warning,
                          ),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => PayslipDialog(payslipId: payslip.id),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                PaginationControls(
                  currentPage: page.currentPage,
                  lastPage: page.lastPage,
                  total: page.total,
                  perPage: page.perPage,
                  onPageChanged: notifier.goToPage,
                  onPerPageChanged: notifier.setPerPage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
