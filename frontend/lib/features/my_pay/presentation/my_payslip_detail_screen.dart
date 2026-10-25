import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../payroll/data/models/payroll.dart';
import '../application/my_pay_notifier.dart';
import '../data/my_pay_repository.dart';

/// One payslip on the phone (docs/teacher-app.md, T4): the net pay first,
/// then the month's days, what was earned and what was taken off - the PDF's
/// content, readable without a PDF viewer. The PDF itself goes to the
/// person's inbox on request, because a phone has no file to keep it in
/// here and an inbox does.
class MyPayslipDetailScreen extends ConsumerWidget {
  const MyPayslipDetailScreen({super.key, required this.payslipId});

  final int payslipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slip = ref.watch(myPayslipProvider(payslipId));

    return Scaffold(
      appBar: AppBar(title: Text(slip.value?.periodLabel ?? 'Payslip')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AsyncValueView<Payslip>(
              value: slip,
              onRetry: () => ref.invalidate(myPayslipProvider(payslipId)),
              data: (context, slip) => _Detail(slip: slip),
            ),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.slip});

  final Payslip slip;

  String _money(String amount) => formatCurrency(double.parse(amount), slip.currencyCode);

  String _days(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final earnings = slip.linesOf(PayComponentType.earning);
    final deductions = slip.linesOf(PayComponentType.deduction);

    return ListView(
      key: const Key('my-payslip'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net pay', style: TextStyle(color: colors.muted)),
                const SizedBox(height: 2),
                Text(
                  _money(slip.netPay),
                  key: const Key('my-payslip-net'),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                StatusBadge(
                  label: slip.isPaid
                      ? 'Paid${slip.paidOn == null ? '' : ' on ${formatIsoDate(slip.paidOn)}'}'
                            '${slip.paymentMode == null ? '' : ' by ${slip.paymentMode!.label}'}'
                      : 'Not paid yet',
                  tone: slip.isPaid ? BadgeTone.success : BadgeTone.warning,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Days',
          rows: [
            ('Working days', _days(slip.workingDays)),
            ('Paid days', _days(slip.paidDays)),
            if (slip.absentDays > 0) ('Absent', _days(slip.absentDays)),
            if (slip.halfDays > 0) ('Half days', '${slip.halfDays}'),
            if (slip.unmarkedDays > 0) ('Not marked', '${slip.unmarkedDays}'),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          key: const Key('my-payslip-earnings'),
          title: 'Earnings',
          rows: [
            for (final line in earnings) (line.name, _money(line.amount)),
            ('Total earnings', _money(slip.grossEarnings)),
          ],
          lastIsTotal: true,
        ),
        const SizedBox(height: 12),
        _Section(
          key: const Key('my-payslip-deductions'),
          title: 'Deductions',
          rows: [
            for (final line in deductions) (line.name, _money(line.amount)),
            ('Total deductions', _money(slip.totalDeductions)),
          ],
          lastIsTotal: true,
        ),
        if (double.parse(slip.shortfall) > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Unpaid days reduced this month by ${_money(slip.shortfall)}.',
            key: const Key('my-payslip-shortfall'),
            style: TextStyle(color: colors.muted, height: 1.35),
          ),
        ],
        const SizedBox(height: 20),
        _EmailMe(slip: slip),
        const SizedBox(height: 8),
        Text(
          '${slip.schoolName} · ${slip.employeeName} (${slip.employeeCode})',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.rows, this.lastIsTotal = false});

  final String title;
  final List<(String, String)> rows;
  final bool lastIsTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++) ...[
              if (lastIsTotal && i == rows.length - 1) const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(rows[i].$1)),
                    Text(
                      rows[i].$2,
                      style: TextStyle(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: lastIsTotal && i == rows.length - 1 ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Email me the PDF": the server sends it to the address on the account.
class _EmailMe extends ConsumerStatefulWidget {
  const _EmailMe({required this.slip});

  final Payslip slip;

  @override
  ConsumerState<_EmailMe> createState() => _EmailMeState();
}

class _EmailMeState extends ConsumerState<_EmailMe> {
  bool _busy = false;
  String? _problem;

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });

    try {
      final message = await ref.read(myPayRepositoryProvider).emailMe(widget.slip.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _problem = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_problem != null) ...[
          Container(
            key: const Key('my-payslip-email-problem'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(_problem!, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            key: const Key('my-payslip-email'),
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.mail_outline),
            label: Text(_busy ? 'Sending…' : 'Email me the PDF'),
          ),
        ),
      ],
    );
  }
}
