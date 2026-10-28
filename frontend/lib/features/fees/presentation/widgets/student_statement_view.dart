import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../application/student_fees_providers.dart';
import '../../data/models/student_fees.dart';
import '../../data/money_text.dart';

/// One student's fees for a year: the totals, and every installment charged
/// to them in date order (docs/fees.md, F2).
class StudentStatementView extends ConsumerWidget {
  const StudentStatementView({super.key, required this.studentId, this.academicYearId, required this.onBack});

  final int studentId;
  final int? academicYearId;
  final VoidCallback onBack;

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
            data: (context, statement) => _Statement(statement: statement),
          ),
        ),
      ],
    );
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.statement});

  final StudentFeeStatement statement;

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
        Text(student.name, style: Theme.of(context).textTheme.headlineSmall),
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
                  _DueRow(due: due, money: _money),
                  if (due != statement.dues.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
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

class _DueRow extends StatelessWidget {
  const _DueRow({required this.due, required this.money});

  final FeeDue due;
  final String Function(String) money;

  static const _reasons = {
    'class_changed': 'moved to another class',
    'route_changed': 'moved to another bus route',
    'left': 'no longer at the school',
    'fee_changed': 'the fee was changed',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cancelled = due.isCancelled;
    final strike = cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null;

    final (badge, tone) = switch (due) {
      FeeDue(isCancelled: true) => ('Cancelled', BadgeTone.neutral),
      FeeDue(isOverdue: true) => ('Overdue', BadgeTone.danger),
      FeeDue(status: FeeDueStatus.paid) => ('Paid', BadgeTone.success),
      FeeDue(status: FeeDueStatus.partial) => ('Part paid', BadgeTone.info),
      FeeDue(status: FeeDueStatus.waived) => ('Waived', BadgeTone.neutral),
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
                Text(due.label, style: const TextStyle(fontWeight: FontWeight.w600).merge(strike)),
                Text(
                  cancelled && due.cancelledReason != null
                      ? 'Was due ${formatDate(due.dueDate)} - not charged: ${_reasons[due.cancelledReason] ?? due.cancelledReason}'
                      : 'Due ${formatDate(due.dueDate)}',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ],
            ),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(money(due.amount), style: strike),
                if (!cancelled && (centsOf(due.paidAmount) ?? 0) > 0)
                  Text('Paid ${money(due.paidAmount)}', style: TextStyle(color: colors.success)),
                if (!cancelled)
                  Text('Balance ${money(due.balance)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                StatusBadge(label: badge, tone: tone),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
