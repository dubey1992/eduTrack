import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../application/academic_term_notifier.dart';
import '../data/models/academic_term.dart';
import '../data/models/academic_year.dart';

/// The terms of one academic year - add, edit and delete, like the transport
/// module's Manage Stops dialog (docs/assessments.md).
///
/// [canManage] is false for the read-only roles, which still see the terms:
/// a teacher needs to know when Term 1 ends even though they cannot move it.
class ManageTermsDialog extends ConsumerWidget {
  const ManageTermsDialog({super.key, required this.year, required this.canManage});

  final AcademicYear year;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final termsState = ref.watch(academicTermsProvider(year.id));

    return AlertDialog(
      title: Text('Terms · ${year.name}'),
      content: ConstrainedBox(
        // Bounded so the spinner does not stretch the dialog to the full
        // viewport height before the terms arrive.
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 460, maxHeight: 420),
        child: AsyncValueView<List<AcademicTerm>>(
          value: termsState,
          onRetry: () => ref.read(academicTermsProvider(year.id).notifier).refresh(),
          isEmpty: (terms) => terms.isEmpty,
          emptyBuilder: (context) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No terms in this year yet. Results are filed under a term, so add them before the tests start.',
            ),
          ),
          data: (context, terms) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final term in terms) _TermRow(year: year, term: term, canManage: canManage)],
              ),
            );
          },
        ),
      ),
      actions: [
        if (canManage)
          TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => TermFormDialog(
                year: year,
                nextSequenceNumber: ref.read(academicTermsProvider(year.id).notifier).nextSequenceNumber,
              ),
            ),
            child: const Text('Add Term'),
          ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

class _TermRow extends ConsumerWidget {
  const _TermRow({required this.year, required this.term, required this.canManage});

  final AcademicYear year;
  final AcademicTerm term;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 14, child: Text('${term.sequenceNumber}', style: const TextStyle(fontSize: 12))),
      title: Text(term.name),
      subtitle: Text('${formatDate(term.startDate)} - ${formatDate(term.endDate)}'),
      trailing: canManage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit term',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => TermFormDialog(year: year, term: term, nextSequenceNumber: term.sequenceNumber),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete term',
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove term?'),
        content: Text('This will remove "${term.name}" from ${year.name}. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(academicTermsProvider(year.id).notifier).deleteTerm(term);
      messenger.showSnackBar(SnackBar(content: Text('${term.name} was removed.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

/// Add (no [term]) or edit (with [term]) one term of a year.
class TermFormDialog extends ConsumerStatefulWidget {
  const TermFormDialog({super.key, required this.year, this.term, required this.nextSequenceNumber});

  final AcademicYear year;
  final AcademicTerm? term;
  final int nextSequenceNumber;

  @override
  ConsumerState<TermFormDialog> createState() => _TermFormDialogState();
}

class _TermFormDialogState extends ConsumerState<TermFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.term?.name ?? '');
  late final _sequenceController = TextEditingController(text: '${widget.nextSequenceNumber}');
  late DateTime? _startDate = widget.term?.startDate;
  late DateTime? _endDate = widget.term?.endDate;

  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.term != null;

  @override
  void dispose() {
    _nameController.dispose();
    _sequenceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      // The year's own span, so a term cannot be picked outside it in the
      // first place. The backend refuses it as well - this only saves a
      // round trip.
      initialDate: (isStart ? _startDate : _endDate) ?? widget.year.startDate,
      firstDate: widget.year.startDate,
      lastDate: widget.year.endDate,
    );
    if (picked == null) return;

    setState(() => isStart ? _startDate = picked : _endDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    if (_startDate == null || _endDate == null) {
      setState(() => _errorMessage = 'Both a start and end date are required.');
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      setState(() => _errorMessage = 'The end date must be after the start date.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = const {};
    });

    try {
      final notifier = ref.read(academicTermsProvider(widget.year.id).notifier);
      final name = _nameController.text.trim();
      final sequence = int.parse(_sequenceController.text.trim());

      if (_isEdit) {
        await notifier.editTerm(
          widget.term!,
          name: name,
          sequenceNumber: sequence,
          startDate: _startDate!,
          endDate: _endDate!,
        );
      } else {
        await notifier.addTerm(name: name, sequenceNumber: sequence, startDate: _startDate!, endDate: _endDate!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEdit ? 'Term updated.' : 'Term added.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // A dates problem is shown under the dates it is about, so the
          // banner does not repeat what the fields already say.
          final aboutFields = _fieldErrors.keys.any(
            (key) => const {'name', 'sequence_number', 'start_date', 'end_date'}.contains(key),
          );
          _errorMessage = aboutFields ? null : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Term' : 'Add Term'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Name (e.g. Term 1)', errorText: _fieldErrors['name']?.first),
                  maxLength: 50,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                TextFormField(
                  controller: _sequenceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Order within the year',
                    errorText: _fieldErrors['sequence_number']?.first,
                  ),
                  validator: (v) {
                    final parsed = int.tryParse(v?.trim() ?? '');
                    return (parsed == null || parsed < 1) ? 'Enter a valid order (1 or more)' : null;
                  },
                ),
                const SizedBox(height: 10),
                _DateField(
                  label: 'Start date',
                  value: _startDate == null ? null : dateFormat.format(_startDate!),
                  error: _fieldErrors['start_date']?.first,
                  onTap: () => _pickDate(isStart: true),
                ),
                const SizedBox(height: 10),
                _DateField(
                  label: 'End date',
                  value: _endDate == null ? null : dateFormat.format(_endDate!),
                  error: _fieldErrors['end_date']?.first,
                  onTap: () => _pickDate(isStart: false),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.error, required this.onTap});

  final String label;
  final String? value;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, errorText: error),
        child: Text(value ?? 'Select a date'),
      ),
    );
  }
}
