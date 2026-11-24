import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
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
import '../../../today/presentation/staff_words.dart';

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
    final l10n = context.l10n;

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
                    Text(l10n.staffInCredit, style: TextStyle(color: colors.muted, fontSize: 13)),
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
                  label: Text(l10n.staffHistory),
                ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: () => showRefundDialog(context, statement),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.staffRefund),
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
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffCreditHistoryFor(widget.student.name)),
      content: SizedBox(
        width: 620,
        height: 460,
        child: AsyncValueView(
          value: ref.watch(studentCreditHistoryProvider(query)),
          onRetry: () => ref.invalidate(studentCreditHistoryProvider(query)),
          data: (context, page) {
            if (page.items.isEmpty) {
              return Center(child: Text(l10n.staffNoCreditMoved));
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
                      Text(l10n.staffPageOf(page.currentPage, page.lastPage)),
                      IconButton(
                        tooltip: l10n.staffNewer,
                        onPressed: _page > 1 ? () => setState(() => _page--) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: l10n.staffOlder,
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
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.staffClose))],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final FeeCreditEntry entry;

  String _about(AppLocalizations l10n) => [
    if (entry.dueLabel != null) entry.dueLabel!,
    if (entry.receiptNumber != null) l10n.staffReceiptNumber(entry.receiptNumber!),
    if (entry.paymentModeLabel != null) entry.paymentModeLabel!,
    if (entry.reference != null) entry.reference!,
    if (entry.note != null) entry.note!,
    if (entry.createdByName != null) l10n.staffByLower(entry.createdByName!),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final amount = formatCurrency((centsOf(entry.size) ?? 0) / 100, entry.currencyCode);
    final about = _about(context.l10n);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.isIn ? Icons.south_west : Icons.north_east,
        color: entry.isIn ? colors.success : colors.muted,
      ),
      title: Text(entry.kindLabel),
      subtitle: Text(
        [formatDate(entry.entryDate), if (about.isNotEmpty) about].join(' · '),
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
    ..showSnackBar(SnackBar(content: Text(context.l10n.staffRefundRecorded(refunded))));
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

    if (cents == null || cents == 0) return context.l10n.staffEnterAmountAboveZero;
    if (cents > held) return context.l10n.staffOnlyHeldInCredit(_money(held));
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
          _error = failure.localizedMessage(context);
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
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffRefundCreditFor(widget.statement.student.name)),
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
                  l10n.staffHoldsCredit(_money(centsOf(_credit.balance) ?? 0)),
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 12),
                if (held.length > 1) ...[
                  DropdownButtonFormField<FeeCreditBalance>(
                    initialValue: _credit,
                    decoration: InputDecoration(labelText: l10n.staffCurrency),
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
                          labelText: l10n.staffAmountRefunded,
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
                            labelText: l10n.staffDateRefunded,
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
                        decoration: InputDecoration(
                          labelText: l10n.staffPaidBackBy,
                          errorText: _fieldErrors['payment_mode'],
                        ),
                        items: [
                          for (final mode in PaymentMode.values)
                            DropdownMenuItem(value: mode, child: Text(paymentModeLabel(l10n, mode.wire, mode.label))),
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
                          labelText: _mode.needsReference ? l10n.staffChequeNumber : l10n.staffReferenceOptional,
                          counterText: '',
                          errorText: _fieldErrors['reference'],
                          errorMaxLines: 3,
                        ),
                        validator: (value) =>
                            _mode.needsReference && (value ?? '').trim().isEmpty ? l10n.staffEnterChequeNumber : null,
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
                    labelText: l10n.staffReason,
                    hintText: l10n.staffRefundReasonHint,
                    errorText: _fieldErrors['reason'],
                  ),
                  validator: (value) => (value ?? '').trim().length < 3 ? l10n.staffSayWhyRefund : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.staffRecordRefund),
        ),
      ],
    );
  }
}
