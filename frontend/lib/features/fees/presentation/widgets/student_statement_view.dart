import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../application/student_fees_providers.dart';
import '../../data/models/student_fees.dart';
import '../../data/models/fee_receipt.dart';
import '../../data/money_text.dart';
import 'adjustment_actions.dart';
import 'receipt_actions.dart';
import 'record_payment_dialog.dart';

/// One student's fees for a year: the totals, every installment charged to
/// them in date order (docs/fees.md, F2), and the payments made (F3) - with
/// Record Payment for those who take money.
class StudentStatementView extends ConsumerWidget {
  const StudentStatementView({
    super.key,
    required this.studentId,
    this.academicYearId,
    required this.onBack,
    this.canManage = false,
  });

  final int studentId;
  final int? academicYearId;
  final VoidCallback onBack;

  /// Whether this person records and cancels payments.
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (studentId: studentId, academicYearId: academicYearId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('All students'),
            ),
          ),
        ),
        Expanded(
          child: AsyncValueView<StudentFeeStatement>(
            value: ref.watch(studentStatementProvider(query)),
            onRetry: () => ref.invalidate(studentStatementProvider(query)),
            data: (context, statement) => _Statement(statement: statement, canManage: canManage),
          ),
        ),
      ],
    );
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.statement, required this.canManage});

  final StudentFeeStatement statement;
  final bool canManage;

  String _money(String amount) => formatCurrency((centsOf(amount) ?? 0) / 100, statement.currencyCode);

  @override
  Widget build(BuildContext context) {
    final student = statement.student;
    final totals = statement.totals;
    final muted = context.appColors.muted;
    final admitted = student.admissionDate;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(student.name, style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8,
              children: [
                // Anyone who can read the statement can hand it over.
                Consumer(
                  builder: (context, ref, _) => OutlinedButton.icon(
                    onPressed: () => downloadStatement(
                      context,
                      ref,
                      studentId: student.id,
                      academicYearId: statement.academicYearId,
                      fileName: 'statement-${student.admissionNumber}-${statement.academicYearName}.pdf',
                    ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Statement PDF'),
                  ),
                ),
                if (canManage) ...[
                  if (statement.feeHeads.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => showAddDiscountDialog(context, statement),
                      icon: const Icon(Icons.percent),
                      label: const Text('Add Discount'),
                    ),
                  if (statement.payable.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => showRecordPaymentDialog(context, statement),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Record Payment'),
                    ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            'Adm. no. ${student.admissionNumber}',
            if (student.classLabel.isNotEmpty) student.classLabel,
            statement.academicYearName,
            if (admitted != null) 'Joined ${formatDate(admitted)}',
          ].join(' · '),
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Total(label: 'Charged', value: _money(totals.charged)),
            if ((centsOf(totals.discount) ?? 0) > 0) _Total(label: 'Discount', value: _money(totals.discount)),
            _Total(label: 'Paid', value: _money(totals.paid)),
            if ((centsOf(totals.waived) ?? 0) > 0) _Total(label: 'Waived', value: _money(totals.waived)),
            _Total(label: 'Balance', value: _money(totals.balance)),
            _Total(label: 'Overdue', value: _money(totals.overdue), alarming: (centsOf(totals.overdue) ?? 0) > 0),
          ],
        ),
        const SizedBox(height: 20),
        if (statement.dues.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Nothing has been charged for ${statement.academicYearName}. Fees are charged once they are published '
              'for this student\'s class or bus route.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final due in statement.dues) ...[
                  _DueRow(due: due, money: _money, canManage: canManage),
                  if (due != statement.dues.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
        if (statement.concessions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Discounts', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final concession in statement.concessions) ...[
                  _DiscountRow(concession: concession, money: _money, canManage: canManage),
                  if (concession != statement.concessions.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
        if (statement.receipts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Payments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final receipt in statement.receipts) ...[
                  _ReceiptRow(receipt: receipt, money: _money, canManage: canManage),
                  if (receipt != statement.receipts.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, this.alarming = false});

  final String label;
  final String value;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: alarming ? colors.danger : null),
          ),
        ],
      ),
    );
  }
}

class _DueRow extends ConsumerWidget {
  const _DueRow({required this.due, required this.money, required this.canManage});

  final FeeDue due;
  final String Function(String) money;
  final bool canManage;

  static const _reasons = {
    'class_changed': 'moved to another class',
    'route_changed': 'moved to another bus route',
    'left': 'no longer at the school',
    'fee_changed': 'the fee was changed',
  };

  String _subtitle() {
    if (due.isCancelled && due.cancelledReason != null) {
      return 'Was due ${formatDate(due.dueDate)} - not charged: ${_reasons[due.cancelledReason] ?? due.cancelledReason}';
    }
    if (due.isWaived) {
      return 'Was due ${formatDate(due.dueDate)} - waived${due.waiveReason == null ? '' : ': ${due.waiveReason}'}';
    }
    return due.isLateFine ? 'Added ${formatDate(due.dueDate)}' : 'Due ${formatDate(due.dueDate)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final struck = due.isCancelled || due.isWaived;
    final strike = struck ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    final discounted = (centsOf(due.discountAmount) ?? 0) > 0;

    final (badge, tone) = switch (due) {
      FeeDue(isCancelled: true) => ('Cancelled', BadgeTone.neutral),
      FeeDue(isWaived: true) => ('Waived', BadgeTone.neutral),
      FeeDue(isCoveredByDiscount: true) => ('Covered by discount', BadgeTone.info),
      FeeDue(isOverdue: true) => ('Overdue', BadgeTone.danger),
      FeeDue(status: FeeDueStatus.paid) => ('Paid', BadgeTone.success),
      FeeDue(status: FeeDueStatus.partial) => ('Part paid', BadgeTone.info),
      _ => ('Due', BadgeTone.warning),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // Full width, so the label sits left and the figures right; a Wrap is
      // otherwise only as wide as what is in it, and the card centres it.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(due.label, style: const TextStyle(fontWeight: FontWeight.w600).merge(strike)),
                    if (due.isLateFine) const StatusBadge(label: 'Late fine', tone: BadgeTone.danger),
                  ],
                ),
                Text(_subtitle(), style: TextStyle(color: colors.muted, fontSize: 13)),
              ],
            ),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(money(due.amount), style: strike),
                if (!due.isCancelled && discounted)
                  Text('Discount ${money(due.discountAmount)}', style: TextStyle(color: colors.info)),
                if (!due.isCancelled && (centsOf(due.paidAmount) ?? 0) > 0)
                  Text('Paid ${money(due.paidAmount)}', style: TextStyle(color: colors.success)),
                if (!struck) Text('Balance ${money(due.balance)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                StatusBadge(label: badge, tone: tone),
                if (canManage && due.isOpen)
                  IconButton(
                    tooltip: 'Waive',
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    onPressed: () => waiveDue(context, ref, due),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscountRow extends ConsumerWidget {
  const _DiscountRow({required this.concession, required this.money, required this.canManage});

  final FeeConcession concession;
  final String Function(String) money;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final amount = concession.isPercent ? '${concession.value}%' : money(concession.value);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$amount off each ${concession.feeHeadName ?? 'fee'} installment',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    concession.reason,
                    if (concession.createdByName != null) 'by ${concession.createdByName}',
                  ].join(' · '),
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ],
            ),
            if (canManage)
              TextButton(onPressed: () => revokeDiscount(context, ref, concession), child: const Text('End discount')),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends ConsumerWidget {
  const _ReceiptRow({required this.receipt, required this.money, required this.canManage});

  final ReceiptSummary receipt;
  final String Function(String) money;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final strike = receipt.isCancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(receipt.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w600).merge(strike)),
                Text(
                  '${formatDate(receipt.receiptDate)} · ${receipt.paymentModeLabel}',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(money(receipt.amount), style: strike),
                if (receipt.isCancelled) const StatusBadge(label: 'Cancelled', tone: BadgeTone.neutral),
                IconButton(
                  tooltip: 'Download receipt',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => downloadReceipt(context, ref, id: receipt.id, number: receipt.receiptNumber),
                ),
                if (canManage && !receipt.isCancelled)
                  IconButton(
                    tooltip: 'Cancel receipt',
                    icon: Icon(Icons.block, color: colors.danger),
                    onPressed: () => cancelReceipt(context, ref, id: receipt.id, number: receipt.receiptNumber),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
