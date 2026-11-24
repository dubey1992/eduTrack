import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
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
  final l10n = context.l10n;

  try {
    final bytes = await ref.read(feeReceiptActionsProvider).pdf(id);
    saveBytes(fileName: '$number.pdf', bytes: bytes, mimeType: 'application/pdf');
  } catch (error) {
    _say(
      messenger,
      error is Failure && context.mounted
          ? error.localizedMessage(context)
          : _problem(error, l10n.staffReceiptDownloadFailed),
    );
  }
}

/// The student's statement for a year, as a PDF.
Future<void> downloadStatement(
  BuildContext context,
  WidgetRef ref, {
  required int studentId,
  required int academicYearId,
  required String fileName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  try {
    final bytes = await ref.read(feeReceiptActionsProvider).statementPdf(studentId, academicYearId: academicYearId);
    saveBytes(fileName: fileName, bytes: bytes, mimeType: 'application/pdf');
  } catch (error) {
    _say(
      messenger,
      error is Failure && context.mounted
          ? error.localizedMessage(context)
          : _problem(error, l10n.staffStatementDownloadFailed),
    );
  }
}

Future<void> emailReceipt(BuildContext context, WidgetRef ref, {required int id}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  try {
    await ref.read(feeReceiptActionsProvider).email(id);
    _say(messenger, l10n.staffReceiptEmailed);
  } catch (error) {
    // The server names the field ("no guardian email address"); say that.
    final failure = error is Failure ? error : null;
    final detail = failure?.validationErrors.values.expand((messages) => messages).firstOrNull;
    _say(
      messenger,
      detail ??
          (error is Failure && context.mounted
              ? error.localizedMessage(context)
              : _problem(error, l10n.staffReceiptEmailFailed)),
    );
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
  final l10n = context.l10n;

  try {
    await ref.read(feeReceiptActionsProvider).cancel(id, reason: reason);
    _say(messenger, l10n.staffReceiptCancelled(number));
    return true;
  } catch (error) {
    _say(
      messenger,
      error is Failure && context.mounted
          ? error.localizedMessage(context)
          : _problem(error, l10n.staffReceiptCancelFailed),
    );
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
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffCancelReceiptQ(widget.number)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.staffCancelReceiptBody),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLength: 500,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.staffReason, hintText: l10n.staffCancelReceiptHint),
                validator: (value) => (value ?? '').trim().length < 3 ? l10n.staffSayWhyCancel : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.staffKeepReceipt)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: _confirm,
          child: Text(l10n.staffCancelReceipt),
        ),
      ],
    );
  }
}
