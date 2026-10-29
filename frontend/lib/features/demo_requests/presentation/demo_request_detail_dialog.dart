import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../application/demo_request_notifier.dart';
import '../data/models/demo_request.dart';
import 'demo_request_screen.dart';

Future<void> showDemoRequestDetail(BuildContext context, DemoRequest request) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DemoRequestDetailDialog(request: request),
  );
}

/// Everything a school told us, and what can be done about it: move it along
/// (New, Scheduled, Done, Declined) and keep a note of what was agreed.
class _DemoRequestDetailDialog extends ConsumerStatefulWidget {
  const _DemoRequestDetailDialog({required this.request});

  final DemoRequest request;

  @override
  ConsumerState<_DemoRequestDetailDialog> createState() => _DemoRequestDetailDialogState();
}

class _DemoRequestDetailDialogState extends ConsumerState<_DemoRequestDetailDialog> {
  late final TextEditingController _notes = TextEditingController(text: widget.request.notes ?? '');
  late DemoRequestStatus _status = widget.request.status;
  bool _isSaving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    // Captured before the await: by the time the snackbar shows, this dialog
    // has been popped and its context is gone.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(demoRequestNotifierProvider.notifier)
          .review(widget.request, status: _status.apiValue, notes: _notes.text.trim());
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Request updated.')));
    } catch (error) {
      // The dialog stays open with what was chosen, so nothing is retyped.
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }

    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(request.schoolName)),
          DemoRequestStatusBadge(status: request.status),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Detail(label: 'Preferred slot', value: request.preferredSlot),
              _Detail(label: 'Contact', value: request.contactName),
              _Detail(label: 'Email', value: request.email),
              _Detail(label: 'Phone', value: request.phone),
              _Detail(label: 'Location', value: request.location),
              _Detail(label: 'Expected students', value: request.expectedStudents?.toString() ?? 'Not given'),
              if (request.message != null) _Detail(label: 'Message', value: request.message!),
              _Detail(label: 'Received', value: request.submittedAt),
              if (request.reviewedByName != null)
                _Detail(label: 'Last updated by', value: '${request.reviewedByName} - ${request.reviewedAt ?? ''}'),
              const Divider(height: 28),
              DropdownButtonFormField<DemoRequestStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  for (final status in DemoRequestStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: (value) => setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  helperText: 'What was agreed, and what happens next.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
