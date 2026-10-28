import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../application/fee_setup_providers.dart';
import '../../data/models/fee_head.dart';

/// Adds a fee type, or renames [head]. Returns the saved head, or null if
/// cancelled.
Future<FeeHead?> showFeeHeadDialog(BuildContext context, {int? schoolId, FeeHead? head}) {
  return showDialog<FeeHead>(
    context: context,
    builder: (context) => _FeeHeadDialog(schoolId: schoolId, head: head),
  );
}

class _FeeHeadDialog extends ConsumerStatefulWidget {
  const _FeeHeadDialog({required this.schoolId, required this.head});

  final int? schoolId;
  final FeeHead? head;

  @override
  ConsumerState<_FeeHeadDialog> createState() => _FeeHeadDialogState();
}

class _FeeHeadDialogState extends ConsumerState<_FeeHeadDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.head?.name ?? '');

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final actions = ref.read(feeSetupActionsProvider);
    final name = _name.text.trim();

    try {
      final head = widget.head;
      final saved = head == null
          ? await actions.createHead(name: name, schoolId: widget.schoolId)
          : await actions.renameHead(head.id, name);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(head == null ? 'Fee type "${saved.name}" added.' : 'Renamed to "${saved.name}".')),
        );
      Navigator.of(context).pop(saved);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() => _error = failure.validationErrors['name']?.join(' ') ?? failure.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.head == null ? 'Add fee type' : 'Rename fee type'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Tuition, Admission, Exam',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onFieldSubmitted: (_) => _save(),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a name for the fee type.' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.head == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
