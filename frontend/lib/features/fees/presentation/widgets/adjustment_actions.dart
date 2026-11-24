import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/utils/decimal_input_formatter.dart';
import '../../application/student_fees_providers.dart';
import '../../data/models/student_fees.dart';
import '../../data/money_text.dart';

/// Discounts and waivers on a student's fees (docs/fees.md, F4), shared by
/// the statement and the Discounts list. Each says how it went.

void _say(ScaffoldMessengerState messenger, String message) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks why, then forgives [due]. Returns true when it was waived.
Future<bool> waiveDue(BuildContext context, WidgetRef ref, FeeDue due) async {
  final l10n = context.l10n;
  final reason = await _askReason(
    context,
    title: l10n.staffWaiveQ(due.label),
    message: l10n.staffWaiveBody,
    confirmLabel: l10n.staffWaive,
    hint: l10n.staffWaiveHint,
  );
  if (reason == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(feeAdjustmentActionsProvider).waive(due.id, reason: reason);
    _say(messenger, l10n.staffWaived(due.label));
    return true;
  } catch (error) {
    _say(
      messenger,
      error is Failure ? (context.mounted ? error.localizedMessage(context) : error.message) : l10n.staffWaiveFailed,
    );
    return false;
  }
}

/// Asks first, then ends [concession]. Returns true when it was ended.
Future<bool> revokeDiscount(BuildContext context, WidgetRef ref, FeeConcession concession) async {
  final l10n = context.l10n;
  final confirmed = await confirmDialog(
    context,
    title: l10n.staffEndDiscountQ,
    message: l10n.staffEndDiscountBody,
    confirmLabel: l10n.staffEndDiscount,
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(feeAdjustmentActionsProvider).revokeDiscount(concession.id);
    _say(messenger, l10n.staffDiscountEnded);
    return true;
  } catch (error) {
    _say(
      messenger,
      error is Failure
          ? (context.mounted ? error.localizedMessage(context) : error.message)
          : l10n.staffDiscountEndFailed,
    );
    return false;
  }
}

/// Adds a discount to one student for the statement's year.
Future<void> showAddDiscountDialog(BuildContext context, StudentFeeStatement statement) {
  return showDialog<void>(
    context: context,
    builder: (context) => _AddDiscountDialog(statement: statement),
  );
}

class _AddDiscountDialog extends ConsumerStatefulWidget {
  const _AddDiscountDialog({required this.statement});

  final StudentFeeStatement statement;

  @override
  ConsumerState<_AddDiscountDialog> createState() => _AddDiscountDialogState();
}

class _AddDiscountDialogState extends ConsumerState<_AddDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _value = TextEditingController();
  final _reason = TextEditingController();

  /// Null = every fee type.
  int? _headId;
  bool _percent = false;
  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      final concession = await ref
          .read(feeAdjustmentActionsProvider)
          .addDiscount(
            studentId: widget.statement.student.id,
            academicYearId: widget.statement.academicYearId,
            feeHeadId: _headId,
            percent: _percent,
            value: textOfCents(centsOf(_value.text)!),
            reason: _reason.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(context.l10n.staffDiscountAdded(concession.duesAffected))));
      Navigator.of(context).pop();
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
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffAddDiscountFor(statement.student.name)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                Text(l10n.staffDiscountIntro(statement.academicYearName)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _headId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.staffFeeType,
                    errorText: _fieldErrors['fee_head_id'],
                    errorMaxLines: 3,
                  ),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(l10n.staffAllFeeTypes)),
                    for (final head in statement.feeHeads)
                      DropdownMenuItem<int?>(value: head.id, child: Text(head.name)),
                  ],
                  onChanged: _saving ? null : (id) => setState(() => _headId = id),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(l10n.staffFixedAmount)),
                    ButtonSegment(value: true, label: Text(l10n.staffPercentage)),
                  ],
                  selected: {_percent},
                  onSelectionChanged: _saving ? null : (selected) => setState(() => _percent = selected.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _value,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalTextInputFormatter()],
                  decoration: InputDecoration(
                    labelText: _percent ? l10n.staffPercentage : l10n.staffAmountIn(statement.currencyCode),
                    suffixText: _percent ? '%' : null,
                    // The owner's rule: a fixed amount comes off every
                    // installment, like a percentage does - said here so
                    // nobody expects a once-a-year figure.
                    helperText: _percent ? l10n.staffOffEach : l10n.staffOffEachNotOnce,
                    errorText: _fieldErrors['value'],
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    final cents = centsOf(value ?? '');
                    if (cents == null || cents == 0) return l10n.staffEnterValueAboveZero;
                    if (_percent && cents > 10000) return l10n.staffPercentMax;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 255,
                  decoration: InputDecoration(
                    labelText: l10n.staffReason,
                    hintText: l10n.staffDiscountReasonHint,
                    errorText: _fieldErrors['reason'],
                  ),
                  validator: (value) => (value ?? '').trim().length < 3 ? l10n.staffSayWhyDiscount : null,
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
              : Text(l10n.staffAddDiscountButton),
        ),
      ],
    );
  }
}

/// A reason, asked for in the app's own dialog. Null when cancelled.
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String hint,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ReasonDialog(title: title, message: message, confirmLabel: confirmLabel, hint: hint),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.message, required this.confirmLabel, required this.hint});

  final String title;
  final String message;
  final String confirmLabel;
  final String hint;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_formKey.currentState!.validate()) Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLength: 255,
                decoration: InputDecoration(labelText: context.l10n.staffReason, hintText: widget.hint),
                validator: (value) => (value ?? '').trim().length < 3 ? context.l10n.staffGiveAReason : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.cancel)),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
