import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/decimal_input_formatter.dart';
import '../../application/student_fees_providers.dart';
import '../../data/models/fee_receipt.dart';
import '../../data/models/student_fees.dart';
import '../../data/money_text.dart';
import '../../../today/presentation/staff_words.dart';
import 'receipt_actions.dart';

/// Takes money for one student's fees (docs/fees.md, F3). By default the
/// payment goes to what is owed oldest first, and anything over what is owed
/// is held as the student's credit (F6); the office can instead choose the
/// installments it pays. Shows the receipt once it is recorded.
Future<void> showRecordPaymentDialog(BuildContext context, StudentFeeStatement statement) async {
  final receipt = await showDialog<({FeeReceipt receipt, bool emailQueued})>(
    context: context,
    builder: (context) => _RecordPaymentDialog(statement: statement),
  );
  if (receipt == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => _ReceiptDone(receipt: receipt.receipt, emailQueued: receipt.emailQueued),
  );
}

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog({required this.statement});

  final StudentFeeStatement statement;

  @override
  ConsumerState<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();

  DateTime _date = DateUtils.dateOnly(DateTime.now());
  PaymentMode _mode = PaymentMode.cash;
  bool _emailGuardian = false;

  /// Choosing installments instead of oldest first.
  bool _choosing = false;

  /// Per installment, when choosing: whether it is paid, and how much.
  late final Map<int, bool> _picked = {for (final due in widget.statement.payable) due.id: false};
  late final Map<int, TextEditingController> _pickedAmount = {
    for (final due in widget.statement.payable) due.id: TextEditingController(text: due.balance),
  };

  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  String _money(String amount) => formatCurrency((centsOf(amount) ?? 0) / 100, widget.statement.currencyCode);

  int get _owedCents => widget.statement.payable.fold(0, (sum, due) => sum + (centsOf(due.balance) ?? 0));

  /// What a spread payment would leave over: held as credit (F6).
  int get _creditCents {
    final cents = centsOf(_amount.text) ?? 0;
    return cents > _owedCents ? cents - _owedCents : 0;
  }

  int get _pickedCents => widget.statement.payable.fold(
    0,
    (sum, due) => sum + ((_picked[due.id] ?? false) ? (centsOf(_pickedAmount[due.id]!.text) ?? 0) : 0),
  );

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    for (final controller in _pickedAmount.values) {
      controller.dispose();
    }
    super.dispose();
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
    if (_saving || !_formKey.currentState!.validate()) return;

    final amountCents = _choosing ? _pickedCents : centsOf(_amount.text);
    if (amountCents == null || amountCents == 0) {
      setState(
        () => _fieldErrors = {
          _choosing ? 'allocations' : 'amount': _choosing
              ? context.l10n.staffTickInstallment
              : context.l10n.staffEnterAmountAboveZero,
        },
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      final result = await ref
          .read(feeReceiptActionsProvider)
          .recordPayment(
            studentId: widget.statement.student.id,
            receiptDate: _date,
            amount: textOfCents(amountCents),
            mode: _mode,
            reference: _reference.text.trim(),
            note: _note.text.trim(),
            allocations: _choosing
                ? [
                    for (final due in widget.statement.payable)
                      if (_picked[due.id] ?? false)
                        (dueId: due.id, amount: textOfCents(centsOf(_pickedAmount[due.id]!.text) ?? 0)),
                  ]
                : null,
            emailToGuardian: _emailGuardian,
          );
      if (mounted) Navigator.of(context).pop(result);
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
    final statement = widget.statement;
    final colors = context.appColors;
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffRecordPaymentFor(statement.student.name)),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
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
                  _owedCents == 0
                      ? l10n.staffOwesNothingFor(statement.academicYearName)
                      : l10n.staffOwesFor(_money(textOfCents(_owedCents)), statement.academicYearName),
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 180,
                      child: InkWell(
                        onTap: _saving ? null : _pickDate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: l10n.staffDateReceived,
                            errorText: _fieldErrors['receipt_date'],
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
                          labelText: l10n.staffPaidBy,
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.staffChooseInstallments),
                  subtitle: Text(l10n.staffChooseInstallmentsOff),
                  value: _choosing,
                  onChanged: _saving || statement.payable.isEmpty ? null : (value) => setState(() => _choosing = value),
                ),
                if (_choosing) _installments() else _amountRow(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  enabled: !_saving,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: l10n.staffNoteOptional, counterText: ''),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.staffEmailReceiptToGuardian),
                  value: _emailGuardian,
                  onChanged: _saving ? null : (value) => setState(() => _emailGuardian = value ?? false),
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
              : Text(l10n.staffRecordPaymentButton),
        ),
      ],
    );
  }

  Widget _amountRow() {
    final l10n = context.l10n;

    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextFormField(
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [DecimalTextInputFormatter()],
            decoration: InputDecoration(
              labelText: l10n.staffAmountReceived,
              errorText: _fieldErrors['amount'],
              errorMaxLines: 4,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        TextButton(
          onPressed: _saving || _owedCents == 0 ? null : () => setState(() => _amount.text = textOfCents(_owedCents)),
          child: Text(l10n.staffPayEverythingOwed),
        ),
        if (_creditCents > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.staffMoreThanOwed(_money(textOfCents(_creditCents))),
              style: TextStyle(color: context.appColors.info),
            ),
          ),
      ],
    );
  }

  Widget _installments() {
    final colors = context.appColors;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final due in widget.statement.payable)
          Row(
            children: [
              Checkbox(
                value: _picked[due.id],
                onChanged: _saving ? null : (value) => setState(() => _picked[due.id] = value ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(due.label),
                    Text(
                      l10n.staffDueAndOwes(formatDate(due.dueDate), _money(due.balance)),
                      style: TextStyle(color: due.isOverdue ? colors.danger : colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _pickedAmount[due.id],
                  enabled: !_saving && (_picked[due.id] ?? false),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalTextInputFormatter()],
                  decoration: InputDecoration(labelText: l10n.staffPay, isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        Text(l10n.staffPaying(_money(textOfCents(_pickedCents))), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_fieldErrors['allocations'] != null || _fieldErrors['amount'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_fieldErrors['allocations'] ?? _fieldErrors['amount']!, style: TextStyle(color: colors.danger)),
          ),
      ],
    );
  }
}

/// The receipt, straight after it was recorded - with the two things the
/// office usually does next.
class _ReceiptDone extends ConsumerWidget {
  const _ReceiptDone({required this.receipt, required this.emailQueued});

  final FeeReceipt receipt;
  final bool emailQueued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String money(String amount) => formatCurrency((centsOf(amount) ?? 0) / 100, receipt.currencyCode);
    final colors = context.appColors;
    final l10n = context.l10n;

    return AlertDialog(
      icon: Icon(Icons.check_circle_outline, color: colors.success, size: 40),
      title: Text(l10n.staffReceiptNumber(receipt.receiptNumber)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.staffReceivedFrom(
                money(receipt.amount),
                receipt.studentName,
                formatDate(receipt.receiptDate),
                paymentModeLabel(l10n, receipt.paymentMode.wire, receipt.paymentMode.label),
              ),
            ),
            const SizedBox(height: 12),
            for (final allocation in receipt.allocations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(allocation.label, style: TextStyle(color: colors.muted)),
                    ),
                    Text(money(allocation.amount)),
                  ],
                ),
              ),
            const Divider(),
            if (receipt.balanceBefore != null) _Line(label: l10n.staffOwedBefore, value: money(receipt.balanceBefore!)),
            _Line(label: l10n.staffPaidNow, value: money(receipt.amount)),
            if ((centsOf(receipt.creditAmount) ?? 0) > 0)
              _Line(label: l10n.staffHeldAsCredit, value: money(receipt.creditAmount)),
            _Line(label: l10n.staffStillOwed, value: money(receipt.balanceAfter ?? receipt.studentBalance), bold: true),
            if (emailQueued) ...[
              const SizedBox(height: 8),
              Text(l10n.staffReceiptBeingEmailed, style: TextStyle(color: colors.muted)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => emailReceipt(context, ref, id: receipt.id),
          icon: const Icon(Icons.outgoing_mail),
          label: Text(l10n.staffEmail),
        ),
        OutlinedButton.icon(
          onPressed: () => downloadReceipt(context, ref, id: receipt.id, number: receipt.receiptNumber),
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.staffDownloadPdf),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.staffDone)),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
