import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/pdf_hand_off.dart';
import '../../../core/widgets/dialog_message.dart';
import '../../auth/application/auth_notifier.dart';
import '../../my_teaching/application/staff_outbox.dart';
import '../../offline_records/data/offline_snapshot.dart';
import '../application/offline_fee_counter.dart';
import '../application/provisional_receipt_pdf.dart';

/// Takes cash or a cheque at the fee counter while the internet is down
/// (docs/offline-web.md, O4), against the dues the computer kept, then
/// offers the provisional receipt. Sent when the line is back.
Future<void> showTakeOfflinePaymentDialog(
  BuildContext context, {
  required OfflineSnapshot snapshot,
  required OfflineStudent student,
}) async {
  final taken = await showDialog<TakenPayment>(
    context: context,
    builder: (_) => TakeOfflinePaymentDialog(snapshot: snapshot, student: student),
  );
  if (taken == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => ProvisionalReceiptDone(payment: taken),
  );
}

class TakeOfflinePaymentDialog extends ConsumerStatefulWidget {
  const TakeOfflinePaymentDialog({super.key, required this.snapshot, required this.student});

  final OfflineSnapshot snapshot;
  final OfflineStudent student;

  @override
  ConsumerState<TakeOfflinePaymentDialog> createState() => _TakeOfflinePaymentDialogState();
}

class _TakeOfflinePaymentDialogState extends ConsumerState<TakeOfflinePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _note = TextEditingController();

  OfflineFeeMode _mode = OfflineFeeMode.cash;
  bool _saving = false;
  String? _error;

  /// What is left on each line once payments already taken offline are counted.
  late final Map<int, double> _left;
  late final List<OfflineDue> _dues;
  final Map<int, bool> _picked = {};
  final Map<int, TextEditingController> _amounts = {};

  @override
  void initState() {
    super.initState();
    final taken = takenOfflineByDue(ref.read(staffOutboxProvider));
    _left = {
      for (final due in widget.snapshot.duesOf(widget.student.id))
        due.id: double.parse(due.balance) - (taken[due.id] ?? 0),
    };
    _dues = [
      for (final due in widget.snapshot.duesOf(widget.student.id))
        if (_left[due.id]! > 0.004) due,
    ];
    for (final due in _dues) {
      _picked[due.id] = false;
      _amounts[due.id] = TextEditingController(text: _left[due.id]!.toStringAsFixed(2));
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _note.dispose();
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<OfflinePart> get _parts => [
    for (final due in _dues)
      if (_picked[due.id]!) (due: due, amount: double.tryParse(_amounts[due.id]!.text.trim()) ?? 0),
  ];

  double get _total => _parts.fold(0, (sum, part) => sum + part.amount);

  String? _amountError(OfflineDue due, String? raw) {
    if (!_picked[due.id]!) return null;
    final value = double.tryParse((raw ?? '').trim());
    if (value == null || value <= 0) return 'Enter an amount';
    if (value > _left[due.id]! + 0.004) return 'Only ${formatCurrency(_left[due.id]!, due.currencyCode)} is owed';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (_parts.isEmpty) {
      setState(() => _error = 'Tick at least one fee to take.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final taken = await ref
          .read(offlineFeeCounterProvider)
          .take(
            snapshot: widget.snapshot,
            student: widget.student,
            parts: _parts,
            mode: _mode,
            takenBy: ref.read(authNotifierProvider).value?.name ?? '',
            reference: _mode == OfflineFeeMode.cheque ? _reference.text.trim() : null,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      if (taken == null) {
        setState(() => _error = 'This payment could not be kept on this computer. Record it once the line is back.');
        return;
      }
      Navigator.of(context).pop(taken);
    } catch (error) {
      debugPrint('Taking a payment offline failed: $error');
      if (mounted) setState(() => _error = 'This payment could not be kept on this computer. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final currency = _dues.isEmpty ? widget.snapshot.school.currencyCode : _dues.first.currencyCode;

    return AlertDialog(
      title: Text('Take a payment - ${widget.student.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colors.warningContainer, borderRadius: BorderRadius.circular(8)),
                child: const DialogMessage(
                  'The internet is down. The family gets a provisional receipt now; the school\'s numbered '
                  'receipt is made when the line is back. Cash and cheques only.',
                ),
              ),
              const SizedBox(height: 12),
              if (_dues.isEmpty)
                Text('Nothing is owed on the copy kept here.', style: TextStyle(color: colors.muted))
              else
                for (final due in _dues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Checkbox(
                          key: Key('offline-pay-due-${due.id}'),
                          value: _picked[due.id],
                          onChanged: _saving ? null : (value) => setState(() => _picked[due.id] = value ?? false),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(due.title),
                              Text(
                                'Due ${formatIsoDate(due.dueDate)} · owes ${formatCurrency(_left[due.id]!, due.currencyCode)}',
                                style: TextStyle(color: colors.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: TextFormField(
                            key: Key('offline-pay-amount-${due.id}'),
                            controller: _amounts[due.id],
                            enabled: !_saving && _picked[due.id]!,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Amount', isDense: true),
                            validator: (raw) => _amountError(due, raw),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<OfflineFeeMode>(
                    segments: [
                      for (final mode in OfflineFeeMode.values) ButtonSegment(value: mode, label: Text(mode.label)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _saving ? null : (selected) => setState(() => _mode = selected.first),
                  ),
                  if (_mode == OfflineFeeMode.cheque)
                    SizedBox(
                      width: 200,
                      child: TextFormField(
                        key: const Key('offline-pay-cheque'),
                        controller: _reference,
                        enabled: !_saving,
                        maxLength: 100,
                        decoration: const InputDecoration(labelText: 'Cheque number', isDense: true, counterText: ''),
                        validator: (raw) => _mode == OfflineFeeMode.cheque && (raw ?? '').trim().isEmpty
                            ? 'Enter the cheque number'
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('offline-pay-note'),
                controller: _note,
                enabled: !_saving,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Note (optional)', isDense: true),
              ),
              const SizedBox(height: 4),
              Text(
                'Total ${formatCurrency(_total, currency)}',
                key: const Key('offline-pay-total'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('offline-pay-error'),
                  style: TextStyle(color: colors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('offline-pay-save'),
          onPressed: _saving || _dues.isEmpty ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Take payment'),
        ),
      ],
    );
  }
}

/// Taken: the provisional number, and the slip to print or save.
class ProvisionalReceiptDone extends ConsumerStatefulWidget {
  const ProvisionalReceiptDone({super.key, required this.payment});

  final TakenPayment payment;

  @override
  ConsumerState<ProvisionalReceiptDone> createState() => _ProvisionalReceiptDoneState();
}

class _ProvisionalReceiptDoneState extends ConsumerState<ProvisionalReceiptDone> {
  bool _making = false;
  String? _error;

  Future<void> _save() async {
    if (_making) return;
    setState(() {
      _making = true;
      _error = null;
    });
    try {
      final bytes = await provisionalReceiptPdf(widget.payment);
      await ref.read(pdfHandOffProvider)(bytes, 'provisional-receipt-${widget.payment.provisionalNumber}.pdf');
    } catch (error) {
      debugPrint('The provisional receipt could not be made: $error');
      if (mounted) setState(() => _error = 'The receipt could not be made. Please try again.');
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    return AlertDialog(
      icon: Icon(Icons.check_circle_outline, color: context.appColors.success),
      title: Text('Taken: ${payment.provisionalNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogMessage(
            '${formatCurrency(payment.total, payment.currencyCode)} from ${payment.student.name}, '
            'kept on this computer. It is sent and receipted when the line is back.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: context.appColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        FilledButton.icon(
          key: const Key('offline-pay-receipt'),
          onPressed: _making ? null : _save,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Provisional receipt'),
        ),
      ],
    );
  }
}
