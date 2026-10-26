import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/secure_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../payroll/data/models/payroll.dart';
import '../application/my_pay_notifier.dart';

/// "My pay" in the School365ai app (docs/teacher-app.md, T4): one card a
/// month, newest first, with what was paid and whether it has been.
class MyPayslipsPhoneScreen extends ConsumerWidget {
  const MyPayslipsPhoneScreen({super.key});

  // Pay is nobody else's business - kept out of screenshots (SecureScreen).
  @override
  Widget build(BuildContext context, WidgetRef ref) => SecureScreen(child: _screen(context, ref));

  Widget _screen(BuildContext context, WidgetRef ref) {
    final payslips = ref.watch(myPayslipsProvider);

    return RefreshIndicator(
      key: const Key('my-pay-refresh'),
      onRefresh: () => ref.read(myPayslipsProvider.notifier).refresh(),
      child: payslips.hasValue
          ? _List(payslips: payslips.requireValue)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _Heading(),
                const SizedBox(height: 16),
                AsyncValueView<MyPayslips>(
                  value: payslips,
                  onRetry: () => ref.read(myPayslipsProvider.notifier).retry(),
                  data: (context, value) => const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Text('My pay', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800));
  }
}

class _List extends ConsumerWidget {
  const _List({required this.payslips});

  final MyPayslips payslips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return ListView(
      key: const Key('my-pay-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const _Heading(),
        const SizedBox(height: 4),
        Text('Your payslips, once the month is finalized.', style: TextStyle(color: colors.muted)),
        const SizedBox(height: 16),
        if (payslips.items.isEmpty)
          Padding(
            key: const Key('my-pay-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: colors.muted),
                const SizedBox(height: 12),
                const Text('No payslips yet.', textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  'A payslip appears here once the school finalizes the month.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted),
                ),
              ],
            ),
          )
        else ...[
          for (final slip in payslips.items) ...[_PayslipCard(slip: slip), const SizedBox(height: 10)],
          if (payslips.hasMore)
            Center(
              child: TextButton(
                key: const Key('my-pay-more'),
                onPressed: () => ref.read(myPayslipsProvider.notifier).loadMore(),
                child: const Text('Show earlier months'),
              ),
            ),
        ],
      ],
    );
  }
}

class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.slip});

  final Payslip slip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Card(
      key: Key('my-pay-${slip.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/pay/${slip.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slip.periodLabel, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      formatCurrency(double.parse(slip.netPay), slip.currencyCode),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text('Net pay', style: TextStyle(fontSize: 12, color: colors.muted)),
                  ],
                ),
              ),
              StatusBadge(
                label: slip.isPaid ? 'Paid' : 'Not paid yet',
                tone: slip.isPaid ? BadgeTone.success : BadgeTone.warning,
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
