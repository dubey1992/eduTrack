import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/file_saver.dart';
import '../../application/student_fees_providers.dart';

/// The three things a receipt can have done to it, shared by every screen
/// that shows one (docs/fees.md, F3). Each says how it went.

void _say(ScaffoldMessengerState messenger, String message) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _problem(Object error, String fallback) => error is Failure ? error.message : fallback;

Future<void> downloadReceipt(BuildContext context, WidgetRef ref, {required int id, required String number}) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final bytes = await ref.read(feeReceiptActionsProvider).pdf(id);
    saveBytes(fileName: '$number.pdf', bytes: bytes, mimeType: 'application/pdf');
  } catch (error) {
    _say(messenger, _problem(error, 'The receipt could not be downloaded. Try again.'));
  }
}

Future<void> emailReceipt(BuildContext context, WidgetRef ref, {required int id}) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    await ref.read(feeReceiptActionsProvider).email(id);
    _say(messenger, 'The receipt is on its way to the guardian.');
  } catch (error) {
    // The server names the field ("no guardian email address"); say that.
    final failure = error is Failure ? error : null;
    final detail = failure?.validationErrors.values.expand((messages) => messages).firstOrNull;
    _say(messenger, detail ?? _problem(error, 'The receipt could not be emailed. Try again.'));
  }
}

/// Asks why, then cancels. Returns true when the receipt was cancelled.
Future<bool> cancelReceipt(BuildContext context, WidgetRef ref, {required int id, required String number}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => _CancelDialog(number: number),
  );
  if (reason == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);

  try {
    await ref.read(feeReceiptActionsProvider).cancel(id, reason: reason);
    _say(messenger, 'Receipt $number cancelled. What it paid is owed again.');
    return true;
  } catch (error) {
    _say(messenger, _problem(error, 'The receipt could not be cancelled. Try again.'));
    return false;
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.number});

  final String number;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
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
      title: Text('Cancel receipt ${widget.number}?'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The receipt stays on record, marked cancelled, and keeps its number. The installments it paid '
                'are owed again. This cannot be undone.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Cheque bounced'),
                validator: (value) =>
                    (value ?? '').trim().length < 3 ? 'Say why the receipt is being cancelled.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep receipt')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: _confirm,
          child: const Text('Cancel receipt'),
        ),
      ],
    );
  }
}
