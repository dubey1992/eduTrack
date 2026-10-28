import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
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
  final reason = await _askReason(
    context,
    title: 'Waive "${due.label}"?',
    message:
        'What is still owed on it is forgiven and it no longer counts as owing. Anything already paid stays '
        'paid. This cannot be undone.',
    confirmLabel: 'Waive',
    hint: 'e.g. Hardship, fine charged in error',
  );
  if (reason == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(feeAdjustmentActionsProvider).waive(due.id, reason: reason);
    _say(messenger, '"${due.label}" waived.');
    return true;
  } catch (error) {
    _say(messenger, error is Failure ? error.message : 'It could not be waived. Try again.');
    return false;
  }
}

/// Asks first, then ends [concession]. Returns true when it was ended.
Future<bool> revokeDiscount(BuildContext context, WidgetRef ref, FeeConcession concession) async {
  final confirmed = await confirmDialog(
    context,
    title: 'End this discount?',
    message:
        'The installments it lowered that are still unpaid go back to their full amount. The discount stays '
        'on record as ended.',
    confirmLabel: 'End discount',
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(feeAdjustmentActionsProvider).revokeDiscount(concession.id);
    _say(messenger, 'Discount ended.');
    return true;
  } catch (error) {
    _say(messenger, error is Failure ? error.message : 'The discount could not be ended. Try again.');
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
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Discount added - ${concession.duesAffected} installment${concession.duesAffected == 1 ? '' : 's'} '
              'lowered.',
            ),
          ),
        );
      Navigator.of(context).pop();
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
    final statement = widget.statement;

    return AlertDialog(
      title: Text('Add discount - ${statement.student.name}'),
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
                Text(
                  'For ${statement.academicYearName}. It lowers each unpaid installment now, and any charged later '
                  'this year. Late fines are never discounted.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _headId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Fee type',
                    errorText: _fieldErrors['fee_head_id'],
                    errorMaxLines: 3,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All fee types')),
                    for (final head in statement.feeHeads)
                      DropdownMenuItem<int?>(value: head.id, child: Text(head.name)),
                  ],
                  onChanged: _saving ? null : (id) => setState(() => _headId = id),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Fixed amount')),
                    ButtonSegment(value: true, label: Text('Percentage')),
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
                    labelText: _percent ? 'Percentage' : 'Amount (${statement.currencyCode})',
                    suffixText: _percent ? '%' : null,
                    // The owner's rule: a fixed amount comes off every
                    // installment, like a percentage does - said here so
                    // nobody expects a once-a-year figure.
                    helperText: _percent ? 'Off each installment.' : 'Off each installment, not once for the year.',
                    errorText: _fieldErrors['value'],
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    final cents = centsOf(value ?? '');
                    if (cents == null || cents == 0) return 'Enter a value above zero.';
                    if (_percent && cents > 10000) return 'A percentage cannot be more than 100.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 255,
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    hintText: 'e.g. Sibling discount, scholarship, staff child',
                    errorText: _fieldErrors['reason'],
                  ),
                  validator: (value) => (value ?? '').trim().length < 3 ? 'Say why the discount is given.' : null,
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
              : const Text('Add discount'),
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
                decoration: InputDecoration(labelText: 'Reason', hintText: widget.hint),
                validator: (value) => (value ?? '').trim().length < 3 ? 'Give a reason.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
