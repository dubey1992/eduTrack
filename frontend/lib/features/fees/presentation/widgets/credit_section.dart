import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/decimal_input_formatter.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../application/student_fees_providers.dart';
import '../../data/models/fee_credit.dart';
import '../../data/models/fee_receipt.dart';
import '../../data/models/student_fees.dart';
import '../../data/money_text.dart';

/// A student's credit on their statement (docs/fees.md, F6): what they hold,
/// its history, and - for those who take money - Refund. Shown only while
/// they hold some.
class CreditSection extends ConsumerWidget {
  const CreditSection({super.key, required this.statement, required this.canManage});

  final StudentFeeStatement statement;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final held = statement.heldCredit;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 10,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.savings_outlined, color: colors.success),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        for (final entry in held)
                          formatCurrency((centsOf(entry.balance) ?? 0) / 100, entry.currencyCode),
                      ].join(' + '),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'In credit - it pays the next fees charged, oldest first.',
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => showCreditHistoryDialog(context, statement.student),
                  icon: const Icon(Icons.history),
                  label: const Text('History'),
                ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: () => showRefundDialog(context, statement),
                    icon: const Icon(Icons.undo),
                    label: const Text('Refund'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -- history ---------------------------------------------------------------------

Future<void> showCreditHistoryDialog(BuildContext context, FeeStudent student) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CreditHistoryDialog(student: student),
  );
}

class _CreditHistoryDialog extends ConsumerStatefulWidget {
  const _CreditHistoryDialog({required this.student});

  final FeeStudent student;

  @override
  ConsumerState<_CreditHistoryDialog> createState() => _CreditHistoryDialogState();
}

class _CreditHistoryDialogState extends ConsumerState<_CreditHistoryDialog> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final query = (studentId: widget.student.id, page: _page);

    return AlertDialog(
      title: Text('Credit history - ${widget.student.name}'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: AsyncValueView(
          value: ref.watch(studentCreditHistoryProvider(query)),
          onRetry: () => ref.invalidate(studentCreditHistoryProvider(query)),
          data: (context, page) {
            if (page.items.isEmpty) {
              return const Center(child: Text('No credit has moved on this account yet.'));
            }

            return Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _HistoryRow(entry: page.items[index]),
                  ),
                ),
                if (page.lastPage > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Page ${page.currentPage} of ${page.lastPage}'),
                      IconButton(
                        tooltip: 'Newer',
                        onPressed: _page > 1 ? () => setState(() => _page--) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Older',
                        onPressed: _page < page.lastPage ? () => setState(() => _page++) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final FeeCreditEntry entry;

  String get _about => [
    if (entry.dueLabel != null) entry.dueLabel!,
    if (entry.receiptNumber != null) 'Receipt ${entry.receiptNumber}',
    if (entry.paymentModeLabel != null) entry.paymentModeLabel!,
    if (entry.reference != null) entry.reference!,
    if (entry.note != null) entry.note!,
    if (entry.createdByName != null) 'by ${entry.createdByName}',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final amount = formatCurrency((centsOf(entry.size) ?? 0) / 100, entry.currencyCode);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.isIn ? Icons.south_west : Icons.north_east,
        color: entry.isIn ? colors.success : colors.muted,
      ),
      title: Text(entry.kindLabel),
      subtitle: Text(
        [formatDate(entry.entryDate), if (_about.isNotEmpty) _about].join(' · '),
        style: TextStyle(color: colors.muted, fontSize: 13),
      ),
      trailing: Text(
        '${entry.isIn ? '+' : '-'} $amount',
        style: TextStyle(fontWeight: FontWeight.w700, color: entry.isIn ? colors.success : null),
      ),
    );
  }
}

// -- refunds ---------------------------------------------------------------------

/// Records money handed back to the family out of their credit.
Future<void> showRefundDialog(BuildContext context, StudentFeeStatement statement) async {
  final refunded = await showDialog<String>(
    context: context,
    builder: (context) => _RefundDialog(statement: statement),
  );
  if (refunded == null || !context.mounted) return;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text('Refund of $refunded recorded.')));
}

class _RefundDialog extends ConsumerStatefulWidget {
  const _RefundDialog({required this.statement});

  final StudentFeeStatement statement;

  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  late FeeCreditBalance _credit = widget.statement.heldCredit.first;
  late final _amount = TextEditingController(text: _credit.balance);
  final _reference = TextEditingController();
  final _reason = TextEditingController();

  DateTime _date = DateUtils.dateOnly(DateTime.now());
  PaymentMode _mode = PaymentMode.cash;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  String _money(int cents) => formatCurrency(cents / 100, _credit.currencyCode);

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  String? _checkAmount(String? value) {
    final cents = centsOf(value ?? '');
    final held = centsOf(_credit.balance) ?? 0;

    if (cents == null || cents == 0) return 'Enter an amount above zero.';
    if (cents > held) return 'Only ${_money(held)} is held in credit.';
    return null;
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      initialDate: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final amount = textOfCents(centsOf(_amount.text)!);

    try {
      await ref
          .read(feeCreditActionsProvider)
          .refund(
            widget.statement.student.id,
            amount: amount,
            currencyCode: _credit.currencyCode,
            refundDate: _date,
            mode: _mode,
            reference: _reference.text.trim(),
            reason: _reason.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(_money(centsOf(amount)!));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _error = failure.message;
          _fieldErrors = {
            for (final entry in failure.validationErrors.entries)
              if (entry.value.isNotEmpty) entry.key: entry.value.join('\n'),
          };
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final held = widget.statement.heldCredit;

    return AlertDialog(
      title: Text('Refund credit - ${widget.statement.student.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          // Once Record refund has been pressed, each message clears as
          // its field is put right.
          autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: colors.onDangerContainer)),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Holds ${_money(centsOf(_credit.balance) ?? 0)} in credit. Record money you have handed back to '
                  'the family - it comes off the credit.',
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 12),
                if (held.length > 1) ...[
                  DropdownButtonFormField<FeeCreditBalance>(
                    initialValue: _credit,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: [for (final entry in held) DropdownMenuItem(value: entry, child: Text(entry.currencyCode))],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _credit = value!;
                            _amount.text = value.balance;
                          }),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: TextFormField(
                        controller: _amount,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [DecimalTextInputFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Amount refunded',
                          errorText: _fieldErrors['amount'],
                          errorMaxLines: 3,
                        ),
                        validator: _checkAmount,
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: InkWell(
                        onTap: _saving ? null : _pickDate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date refunded',
                            errorText: _fieldErrors['refund_date'],
                            errorMaxLines: 3,
                          ),
                          child: Text(formatDate(_date)),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<PaymentMode>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Paid back by', errorText: _fieldErrors['payment_mode']),
                        items: [
                          for (final mode in PaymentMode.values) DropdownMenuItem(value: mode, child: Text(mode.label)),
                        ],
                        onChanged: _saving ? null : (mode) => setState(() => _mode = mode!),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextFormField(
                        controller: _reference,
                        enabled: !_saving,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: _mode.needsReference ? 'Cheque number' : 'Reference (optional)',
                          counterText: '',
                          errorText: _fieldErrors['reference'],
                          errorMaxLines: 3,
                        ),
                        validator: (value) =>
                            _mode.needsReference && (value ?? '').trim().isEmpty ? 'Enter the cheque number.' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    hintText: 'e.g. Left the school',
                    errorText: _fieldErrors['reason'],
                  ),
                  validator: (value) => (value ?? '').trim().length < 3 ? 'Say why the money is refunded.' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Record refund'),
        ),
      ],
    );
  }
}
