import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../schools/presentation/add_school_dialog.dart';
import '../application/early_access_notifier.dart';
import '../data/models/early_access_request.dart';
import 'early_access_screen.dart';

Future<void> showEarlyAccessDetail(BuildContext context, EarlyAccessRequest request) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EarlyAccessDetailDialog(request: request),
  );
}

/// Everything a school told us, and the two things that can be done about it:
/// move it along the pipeline, or onboard it.
class _EarlyAccessDetailDialog extends ConsumerStatefulWidget {
  const _EarlyAccessDetailDialog({required this.request});

  final EarlyAccessRequest request;

  @override
  ConsumerState<_EarlyAccessDetailDialog> createState() => _EarlyAccessDetailDialogState();
}

class _EarlyAccessDetailDialogState extends ConsumerState<_EarlyAccessDetailDialog> {
  late final TextEditingController _notes = TextEditingController(text: widget.request.notes ?? '');
  late EarlyAccessStatus _status = widget.request.status;
  bool _isSaving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final navigator = Navigator.of(context);

    await runAndReport(
      context,
      successMessage: 'Request updated.',
      action: () async {
        await ref
            .read(earlyAccessNotifierProvider.notifier)
            .review(widget.request, status: _status.apiValue, notes: _notes.text.trim());
        navigator.pop();
      },
    );

    if (mounted) setState(() => _isSaving = false);
  }

  void _convert() {
    Navigator.of(context).pop();

    // The request already holds the name, email, phone and location, so the
    // onboarding form starts from what the school told us rather than from
    // somebody retyping it. Creating the school marks the request Converted -
    // that is not something anybody has to remember.
    showDialog<void>(
      context: context,
      builder: (_) => AddSchoolDialog(fromEarlyAccess: widget.request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final isConverted = request.status == EarlyAccessStatus.converted;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(request.schoolName)),
          EarlyAccessStatusBadge(status: request.status),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Detail(label: 'Contact', value: [request.contactName, request.contactRole].nonNulls.join(' - ')),
              _Detail(label: 'Email', value: request.email),
              _Detail(label: 'Phone', value: request.phone),
              _Detail(label: 'Location', value: request.location),
              _Detail(label: 'Expected students', value: request.expectedStudents?.toString() ?? 'Not given'),
              if (request.currentSoftware != null) _Detail(label: 'Uses today', value: request.currentSoftware!),
              if (request.message != null) _Detail(label: 'Message', value: request.message!),
              _Detail(label: 'Received', value: request.submittedAt),
              if (request.reviewedByName != null)
                _Detail(label: 'Last updated by', value: '${request.reviewedByName} - ${request.reviewedAt ?? ''}'),
              if (request.convertedSchoolName != null) _Detail(label: 'Became', value: request.convertedSchoolName!),
              const Divider(height: 28),
              if (isConverted)
                const Text('This school has been onboarded, so there is nothing left to decide.')
              else ...[
                DropdownButtonFormField<EarlyAccessStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status', isDense: true),
                  items: [
                    // Converted is absent on purpose: it means a school
                    // exists, and onboarding one is what sets it.
                    for (final status in EarlyAccessStatus.settable)
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
                    helperText: 'What was said, and what happens next.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (!isConverted) ...[
          OutlinedButton(onPressed: _isSaving ? null : _convert, child: const Text('Onboard this school')),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
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
