import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/decimal_input_formatter.dart';
import '../data/models/payroll.dart';

/// An employee's whole salary: a monthly basic, and the named earnings and
/// deductions on top of it. Saved as one, replacing what was there - see
/// docs/payroll.md.
///
/// Amounts are fixed monthly figures in the school's currency. Pay each month
/// is pro-rated from them by attendance, so the totals here are what a full
/// month pays.
class SalaryDialog extends StatefulWidget {
  const SalaryDialog({super.key, required this.employee, required this.onSave, this.readOnly = false});

  final EmployeeSalary employee;
  final Future<void> Function(String basicSalary, List<SalaryComponent> components) onSave;
  final bool readOnly;

  @override
  State<SalaryDialog> createState() => _SalaryDialogState();
}

class _ComponentRow {
  _ComponentRow({required this.type, String name = '', String amount = ''})
    : name = TextEditingController(text: name),
      amount = TextEditingController(text: amount);

  PayComponentType type;
  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _SalaryDialogState extends State<SalaryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _basic = TextEditingController(text: widget.employee.salary?.basicSalary ?? '');
  late final List<_ComponentRow> _rows = [
    for (final component in widget.employee.salary?.components ?? const <SalaryComponent>[])
      _ComponentRow(type: component.type, name: component.name, amount: component.amount),
  ];
  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _basic.addListener(_recalculate);
    for (final row in _rows) {
      row.amount.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    _basic.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _recalculate() => setState(() {});

  void _add(PayComponentType type) {
    final row = _ComponentRow(type: type)..amount.addListener(_recalculate);
    setState(() => _rows.add(row));
  }

  void _remove(_ComponentRow row) {
    setState(() => _rows.remove(row));
    row.dispose();
  }

  double _sum(PayComponentType type) =>
      _rows.where((row) => row.type == type).fold(0, (total, row) => total + (double.tryParse(row.amount.text) ?? 0));

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await widget.onSave(_basic.text.trim(), [
        for (final row in _rows)
          SalaryComponent(type: row.type, name: row.name.text.trim(), amount: row.amount.text.trim()),
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      setState(() {
        _error = failure.message;
        _fieldErrors = failure.validationErrors;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final currency = employee.salary?.currencyCode ?? employee.schoolCurrencyCode;
    final basic = double.tryParse(_basic.text) ?? 0;
    final earnings = _sum(PayComponentType.earning);
    final deductions = _sum(PayComponentType.deduction);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.readOnly ? 'Salary' : 'Edit Salary'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${employee.name} · ${employee.employeeId}', style: Theme.of(context).textTheme.titleSmall),
                if (employee.designation != null || employee.departmentName != null)
                  Text(
                    [employee.designation, employee.departmentName].whereType<String>().join(' · '),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                TextFormField(
                  controller: _basic,
                  readOnly: widget.readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalTextInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Basic salary (monthly, $currency)',
                    errorText: _serverError('basic_salary'),
                  ),
                  validator: (value) => double.tryParse(value ?? '') == null ? 'Enter the monthly basic salary' : null,
                ),
                const SizedBox(height: 16),
                for (final type in PayComponentType.values) ...[
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        type == PayComponentType.earning ? 'Earnings' : 'Deductions',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (!widget.readOnly)
                        TextButton.icon(
                          onPressed: () => _add(type),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(type == PayComponentType.earning ? 'Add earning' : 'Add deduction'),
                        ),
                    ],
                  ),
                  if (!_rows.any((row) => row.type == type))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('None', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  for (final row in _rows.where((row) => row.type == type)) _componentFields(row),
                  const SizedBox(height: 8),
                ],
                const Divider(),
                _TotalLine(label: 'Gross monthly', value: formatCurrency(basic + earnings, currency)),
                _TotalLine(label: 'Deductions', value: formatCurrency(deductions, currency)),
                _TotalLine(
                  label: 'Net monthly',
                  value: formatCurrency(basic + earnings - deductions, currency),
                  bold: true,
                ),
                const SizedBox(height: 4),
                Text(
                  "A month's pay is pro-rated from these by the days paid.",
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.readOnly ? 'Close' : 'Cancel'),
        ),
        if (!widget.readOnly)
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Salary'),
          ),
      ],
    );
  }

  Widget _componentFields(_ComponentRow row) {
    final index = _rows.indexOf(row);

    final name = TextFormField(
      controller: row.name,
      readOnly: widget.readOnly,
      decoration: InputDecoration(labelText: 'Name', errorText: _serverError('components.$index.name')),
      validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
    );
    final amount = TextFormField(
      controller: row.amount,
      readOnly: widget.readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [DecimalTextInputFormatter()],
      decoration: InputDecoration(labelText: 'Amount', errorText: _serverError('components.$index.amount')),
      validator: (value) => double.tryParse(value ?? '') == null ? 'Required' : null,
    );
    final remove = widget.readOnly
        ? null
        : IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => _remove(row));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Side by side where there is room; on a phone the name sits above
          // the amount rather than squeezing both into unreadable slivers.
          if (constraints.maxWidth < 360) {
            return Column(
              children: [
                name,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: amount),
                    ?remove,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: name),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: amount),
              ?remove,
            ],
          );
        },
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(value, style: style),
        ],
      ),
    );
  }
}
