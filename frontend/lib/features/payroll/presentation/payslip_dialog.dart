import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../data/models/payroll.dart';
import '../data/payroll_repository.dart';
import 'adjustment_dialog.dart';
import 'pay_dialog.dart';

/// One payslip, read fresh from the server: the days it pays for, every line,
/// and - for whoever runs payroll - the draft's adjustments and the payment.
///
/// [onChanged] is called after anything on it changes, so the run behind the
/// dialog can re-read its totals.
class PayslipDialog extends ConsumerStatefulWidget {
  const PayslipDialog({super.key, required this.payslipId, this.canManage = false, this.onChanged});

  final int payslipId;
  final bool canManage;
  final Future<void> Function()? onChanged;

  @override
  ConsumerState<PayslipDialog> createState() => _PayslipDialogState();
}

class _PayslipDialogState extends ConsumerState<PayslipDialog> {
  Payslip? _payslip;
  Failure? _loadFailure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailure = null);

    try {
      final payslip = await ref.read(payrollRepositoryProvider).payslip(widget.payslipId);
      if (mounted) setState(() => _payslip = payslip);
    } catch (error) {
      if (mounted) setState(() => _loadFailure = error is Failure ? error : Failure.unknown(error.toString()));
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs an action that returns the updated payslip, then tells the run.
  Future<void> _apply(Future<Payslip> Function() action, String done) async {
    setState(() => _busy = true);

    try {
      final updated = await action();
      if (mounted) setState(() => _payslip = updated);
      await widget.onChanged?.call();
      _show(done);
    } catch (error) {
      _show(error is Failure ? error.message : error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAdjustment() async {
    final repository = ref.read(payrollRepositoryProvider);
    Payslip? updated;

    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AdjustmentDialog(
        onSave: (type, name, amount, note) async {
          updated = await repository.addAdjustment(widget.payslipId, type: type, name: name, amount: amount, note: note);
        },
      ),
    );

    if (added == true && updated != null && mounted) {
      setState(() => _payslip = updated);
      await widget.onChanged?.call();
      _show('Adjustment added.');
    }
  }

  Future<void> _removeAdjustment(PayslipLine line) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove adjustment?',
      message: '"${line.name}" comes off this draft payslip.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );

    if (!confirmed) return;

    await _apply(() => ref.read(payrollRepositoryProvider).removeAdjustment(widget.payslipId, line.id), 'Adjustment removed.');
  }

  Future<void> _pay() async {
    final repository = ref.read(payrollRepositoryProvider);
    Payslip? updated;

    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => PayDialog(
        title: 'Mark Payslip Paid',
        confirmLabel: 'Mark Paid',
        onPay: (paidOn, mode, reference) async {
          updated = await repository.payPayslip(widget.payslipId, paidOn: paidOn, mode: mode, reference: reference);
        },
      ),
    );

    if (paid == true && updated != null && mounted) {
      setState(() => _payslip = updated);
      await widget.onChanged?.call();
      _show('Payslip marked paid.');
    }
  }

  Future<void> _download() async {
    final payslip = _payslip!;
    setState(() => _busy = true);

    try {
      final bytes = await ref.read(payrollRepositoryProvider).downloadPayslip(payslip.id);
      saveBytes(
        fileName: 'payslip-${payslip.employeeCode}-${payslip.periodLabel.replaceAll(' ', '-')}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    } catch (error) {
      _show(error is Failure ? error.message : error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payslip = _payslip;

    if (payslip == null) {
      return AlertDialog(
        title: const Text('Payslip'),
        content: SizedBox(
          width: 420,
          height: 120,
          child: Center(
            child: _loadFailure == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadFailure!.message, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final draft = payslip.runStatus == PayrollRunStatus.draft;
    String cash(String value) => formatCurrency(double.parse(value), payslip.currencyCode);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('Payslip · ${payslip.periodLabel}')),
          StatusBadge(
            label: draft ? 'Draft' : payslip.status.label,
            tone: draft ? BadgeTone.neutral : (payslip.isPaid ? BadgeTone.success : BadgeTone.warning),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(payslip.employeeName, style: Theme.of(context).textTheme.titleMedium),
              Text(
                [payslip.employeeCode, payslip.designation, payslip.departmentName].whereType<String>().join(' · '),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Fact('Working days', formatDays(payslip.workingDays)),
                  _Fact('Paid days', formatDays(payslip.paidDays)),
                  _Fact('Absent', formatDays(payslip.absentDays)),
                  _Fact('Half days', '${payslip.halfDays}'),
                  _Fact('Not marked (paid)', '${payslip.unmarkedDays}'),
                ],
              ),
              const SizedBox(height: 12),
              for (final type in PayComponentType.values) ...[
                Row(
                  children: [
                    Text(
                      type == PayComponentType.earning ? 'Earnings' : 'Deductions',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                for (final line in payslip.linesOf(type))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: widget.canManage && draft && line.isAdjustment
                        ? IconButton(
                            tooltip: 'Remove adjustment',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: _busy ? null : () => _removeAdjustment(line),
                          )
                        : null,
                    title: Text(line.name),
                    subtitle: Text(
                      line.isAdjustment
                          ? 'Adjustment${line.note == null ? '' : ' - ${line.note}'}'
                          : 'Pro-rated from ${cash(line.fullAmount!)}',
                    ),
                    trailing: Text(cash(line.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (payslip.linesOf(type).isEmpty)
                  Text('None', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
              ],
              const Divider(),
              _Total('Gross earnings', cash(payslip.grossEarnings)),
              _Total('Total deductions', cash(payslip.totalDeductions)),
              _Total('Net pay', cash(payslip.netPay), bold: true),
              if (double.parse(payslip.shortfall) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Deductions exceed earnings by ${cash(payslip.shortfall)}; net pay stops at zero.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              if (payslip.isPaid)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Paid on ${formatIsoDate(payslip.paidOn)} by ${payslip.paymentMode?.label ?? '-'}'
                    '${payslip.paymentReference == null ? '' : ' (${payslip.paymentReference})'}.',
                  ),
                ),
              if (draft)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'This run is a draft; figures may still change.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        OutlinedButton.icon(
          onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download PDF'),
        ),
        if (widget.canManage && draft)
          FilledButton.icon(
            onPressed: _busy ? null : _addAdjustment,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Adjustment'),
          ),
        if (widget.canManage && !draft)
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _apply(() => ref.read(payrollRepositoryProvider).emailPayslip(payslip.id), 'Payslip emailed to the employee.'),
            child: const Text('Email Payslip'),
          ),
        if (widget.canManage && !draft && !payslip.isPaid)
          FilledButton(onPressed: _busy ? null : _pay, child: const Text('Mark Paid')),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14);

    // The label gives way on a narrow screen; the amount never wraps.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(value, style: style),
        ],
      ),
    );
  }
}
