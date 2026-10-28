import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/decimal_input_formatter.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../academic_years/data/models/academic_year.dart';
import '../../application/fee_setup_providers.dart';
import '../../data/models/fee_head.dart';
import '../../data/models/fee_structure.dart';
import '../../data/money_text.dart';
import 'fee_structures_tab.dart';

/// Adds a fee for one class or bus route, or changes [existing]. Returns the
/// saved fee, or null if cancelled.
///
/// [takenHeadIds] are the heads that group already has a fee under, which
/// the server would refuse a second time - so they are not offered.
Future<FeeStructure?> showFeeStructureDialog(
  BuildContext context, {
  required FeeStructureKind kind,
  required FeeGroup group,
  required AcademicYear year,
  int? schoolId,
  FeeStructure? existing,
  Set<int> takenHeadIds = const {},
  bool readOnly = false,
}) {
  return showDialog<FeeStructure>(
    context: context,
    builder: (context) => _FeeStructureDialog(
      kind: kind,
      group: group,
      year: year,
      schoolId: schoolId,
      existing: existing,
      takenHeadIds: takenHeadIds,
      readOnly: readOnly,
    ),
  );
}

/// One installment row of the form.
class _Row {
  _Row({String label = '', String amount = '', this.dueDate})
    : label = TextEditingController(text: label),
      amount = TextEditingController(text: amount);

  final TextEditingController label;
  final TextEditingController amount;
  DateTime? dueDate;

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _FeeStructureDialog extends ConsumerStatefulWidget {
  const _FeeStructureDialog({
    required this.kind,
    required this.group,
    required this.year,
    required this.schoolId,
    required this.existing,
    required this.takenHeadIds,
    required this.readOnly,
  });

  final FeeStructureKind kind;
  final FeeGroup group;
  final AcademicYear year;
  final int? schoolId;
  final FeeStructure? existing;
  final Set<int> takenHeadIds;
  final bool readOnly;

  @override
  ConsumerState<_FeeStructureDialog> createState() => _FeeStructureDialogState();
}

class _FeeStructureDialogState extends ConsumerState<_FeeStructureDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.existing?.amount ?? '');
  final _dueDay = TextEditingController(text: '10');
  late var _frequency = widget.existing?.frequency ?? FeeFrequency.monthly;
  late int? _headId = widget.existing?.feeHeadId;
  late final List<_Row> _rows = [
    for (final installment in widget.existing?.installments ?? const <FeeInstallment>[])
      _Row(label: installment.label, amount: installment.amount, dueDate: installment.dueDate),
  ];

  bool _saving = false;
  bool _planning = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _isRoute => widget.kind == FeeStructureKind.routeFee;
  bool get _editable => !widget.readOnly && !_saving;

  @override
  void dispose() {
    _amount.dispose();
    _dueDay.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Rows taken off the form still have boxes on screen until the next
  /// frame, so their controllers go once it is drawn.
  void _disposeLater(List<_Row> rows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in rows) {
        row.dispose();
      }
    });
  }

  int get _rowsTotal => _rows.fold(0, (sum, row) => sum + (centsOf(row.amount.text) ?? 0));

  /// Asks the server to split the amount by the frequency. Replaces the rows.
  Future<void> _fillInstallments() async {
    final cents = centsOf(_amount.text);
    final dueDay = int.tryParse(_dueDay.text.trim()) ?? 10;

    if (cents == null || cents == 0) {
      setState(() => _fieldErrors = {..._fieldErrors, 'amount': 'Enter the fee amount first.'});
      return;
    }

    if (_rows.isNotEmpty) {
      final replace = await confirmDialog(
        context,
        title: 'Replace the installments?',
        message: 'The installments below are replaced with a new ${_frequency.label.toLowerCase()} split.',
        confirmLabel: 'Replace',
      );
      if (!replace || !mounted) return;
    }

    setState(() {
      _planning = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      final plan = await ref
          .read(feeSetupActionsProvider)
          .installmentPlan(
            academicYearId: widget.year.id,
            frequency: _frequency,
            amount: textOfCents(cents),
            dueDay: dueDay.clamp(1, 31),
          );
      if (!mounted) return;

      setState(() {
        _disposeLater(List.of(_rows));
        _rows
          ..clear()
          ..addAll([for (final step in plan) _Row(label: step.label, amount: step.amount, dueDate: step.dueDate)]);
      });
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  void _showFailure(Object error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    if (!mounted) return;

    setState(() {
      _error = failure.message;
      _fieldErrors = {
        for (final entry in failure.validationErrors.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.join('\n'),
      };
    });
  }

  /// What is wrong with the installments as a whole, or null.
  String? _installmentProblem() {
    if (_rows.isEmpty) return 'Add at least one installment, or fill them in from the frequency.';

    final amount = centsOf(_amount.text);
    DateTime? previous;

    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final number = i + 1;
      if (row.label.text.trim().isEmpty) return 'Installment $number needs a name.';
      if (row.dueDate == null) return 'Installment $number needs a due date.';
      final cents = centsOf(row.amount.text);
      if (cents == null || cents == 0) return 'Installment $number needs an amount above zero.';
      if (previous != null && row.dueDate!.isBefore(previous)) {
        return 'Installment $number is due before installment ${number - 1}. Put them in date order.';
      }
      previous = row.dueDate;
    }

    if (amount != null && _rowsTotal != amount) {
      return 'The installments add up to ${textOfCents(_rowsTotal)}, but the fee is ${textOfCents(amount)}.';
    }

    return null;
  }

  Future<void> _save(FeeHead? transportHead) async {
    if (_saving) return;

    final formValid = _formKey.currentState!.validate();
    final problem = _installmentProblem();
    if (!formValid || problem != null) {
      setState(() => _fieldErrors = {'installments': ?problem});
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final actions = ref.read(feeSetupActionsProvider);
    final amount = textOfCents(centsOf(_amount.text)!);
    final installments = [
      for (final row in _rows)
        InstallmentDraft(
          label: row.label.text.trim(),
          dueDate: row.dueDate!,
          amount: textOfCents(centsOf(row.amount.text)!),
        ),
    ];
    final existing = widget.existing;

    try {
      final saved = existing == null
          ? await actions.createStructure(
              academicYearId: widget.year.id,
              schoolClassId: _isRoute ? null : widget.group.id,
              transportRouteId: _isRoute ? widget.group.id : null,
              feeHeadId: _isRoute ? transportHead!.id : _headId!,
              amount: amount,
              frequency: _frequency,
              installments: installments,
            )
          : await actions.updateStructure(
              existing.id,
              amount: amount,
              frequency: _frequency,
              installments: installments,
            );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              existing == null
                  ? '${saved.feeHeadName} for ${widget.group.name} saved as a draft.'
                  : '${saved.feeHeadName} for ${widget.group.name} saved.',
            ),
          ),
        );
      Navigator.of(context).pop(saved);
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(_Row row) async {
    final year = widget.year;
    final initial = row.dueDate ?? year.startDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: year.startDate,
      lastDate: year.endDate,
      initialDate: initial.isBefore(year.startDate) || initial.isAfter(year.endDate) ? year.startDate : initial,
    );
    if (picked != null) setState(() => row.dueDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final heads = ref.watch(feeHeadsProvider(widget.schoolId));
    final existing = widget.existing;
    final title = widget.readOnly
        ? '${existing!.feeHeadName} - ${widget.group.name}'
        : existing == null
        ? 'Add fee - ${widget.group.name}'
        : 'Edit ${existing.feeHeadName} - ${widget.group.name}';

    final transportHead = heads.value?.where((head) => head.isTransport).firstOrNull;

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[_Banner(message: _error!), const SizedBox(height: 12)],
                Text(widget.year.name, style: TextStyle(color: context.appColors.muted)),
                const SizedBox(height: 12),
                _headField(heads.value ?? const []),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(width: 240, child: _amountField()),
                    SizedBox(width: 180, child: _frequencyField()),
                    if (_frequency.usesDueDay) SizedBox(width: 120, child: _dueDayField()),
                  ],
                ),
                const SizedBox(height: 16),
                _installments(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(widget.readOnly ? 'Close' : 'Cancel'),
        ),
        if (!widget.readOnly)
          FilledButton(
            onPressed: _saving || (_isRoute && transportHead == null) ? null : () => _save(transportHead),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(existing == null ? 'Save as draft' : 'Save'),
          ),
      ],
    );
  }

  Widget _headField(List<FeeHead> heads) {
    final existing = widget.existing;

    // A route's fee is always the Transport head, and an existing fee keeps
    // its head - delete the draft and add it again to change it.
    if (_isRoute || existing != null) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Fee type'),
        child: Text(existing?.feeHeadName ?? 'Transport'),
      );
    }

    final offered = [
      for (final head in heads)
        if (head.isActive && !head.isTransport && !widget.takenHeadIds.contains(head.id)) head,
    ];

    return DropdownButtonFormField<int>(
      initialValue: _headId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Fee type',
        helperText: offered.isEmpty ? 'Every fee type already has a fee here. Add a new type under Fee Types.' : null,
        helperMaxLines: 2,
        errorText: _fieldErrors['fee_head_id'],
        errorMaxLines: 3,
      ),
      items: [for (final head in offered) DropdownMenuItem(value: head.id, child: Text(head.name))],
      onChanged: _editable ? (id) => setState(() => _headId = id) : null,
      validator: (id) => id == null ? 'Choose a fee type.' : null,
    );
  }

  Widget _amountField() {
    return TextFormField(
      controller: _amount,
      enabled: _editable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [DecimalTextInputFormatter()],
      decoration: InputDecoration(
        labelText: 'Amount for the year',
        errorText: _fieldErrors['amount'],
        errorMaxLines: 3,
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        final cents = centsOf(value ?? '');
        if (cents == null || cents == 0) return 'Enter an amount above zero.';
        return null;
      },
    );
  }

  Widget _frequencyField() {
    return DropdownButtonFormField<FeeFrequency>(
      initialValue: _frequency,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Frequency', errorText: _fieldErrors['frequency'], errorMaxLines: 4),
      items: [
        for (final frequency in FeeFrequency.values) DropdownMenuItem(value: frequency, child: Text(frequency.label)),
      ],
      onChanged: _editable ? (frequency) => setState(() => _frequency = frequency!) : null,
    );
  }

  Widget _dueDayField() {
    return TextFormField(
      controller: _dueDay,
      enabled: _editable,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Due on day'),
      validator: (value) {
        final day = int.tryParse((value ?? '').trim());
        return day == null || day < 1 || day > 31 ? '1 to 31' : null;
      },
    );
  }

  Widget _installments() {
    final colors = context.appColors;
    final amount = centsOf(_amount.text);
    final matches = amount != null && amount == _rowsTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('Installments', style: Theme.of(context).textTheme.titleSmall),
            if (_editable)
              OutlinedButton.icon(
                onPressed: _planning ? null : _fillInstallments,
                icon: _planning
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high_outlined, size: 18),
                label: Text('Fill in ${_frequency.label.toLowerCase()}'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _rows.length; i++) _rowEditor(i),
        if (_editable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_Row())),
              icon: const Icon(Icons.add),
              label: const Text('Add installment'),
            ),
          ),
        if (_rows.isNotEmpty)
          Text(
            'Installments total ${textOfCents(_rowsTotal)}'
            '${amount == null ? '' : ' of ${textOfCents(amount)}'}',
            style: TextStyle(color: matches ? colors.success : colors.warning, fontWeight: FontWeight.w600),
          ),
        if (_fieldErrors['installments'] != null) ...[
          const SizedBox(height: 6),
          Text(_fieldErrors['installments']!, style: TextStyle(color: colors.danger)),
        ],
      ],
    );
  }

  Widget _rowEditor(int index) {
    final row = _rows[index];

    return Padding(
      // Keyed to the row, so removing one from the middle does not hand its
      // neighbours' boxes to the wrong installment.
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(padding: const EdgeInsets.only(top: 14), child: Text('${index + 1}.')),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: row.label,
              enabled: _editable,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Name', isDense: true, counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: _editable ? () => _pickDate(row) : null,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Due date', isDense: true),
                child: Text(row.dueDate == null ? 'Choose' : formatDate(row.dueDate!)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.amount,
              enabled: _editable,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalTextInputFormatter()],
              decoration: const InputDecoration(labelText: 'Amount', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_editable)
            IconButton(
              tooltip: 'Remove installment',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _disposeLater([_rows.removeAt(index)])),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(message, style: TextStyle(color: colors.onDangerContainer)),
    );
  }
}
