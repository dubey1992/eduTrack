import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/searchable_dropdown.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../payments/data/models/payment.dart';
import '../application/advances_notifier.dart';
import '../data/models/payroll.dart';
import '../data/payroll_repository.dart';

/// Everybody payroll can pay at a school, for the employee picker. Every
/// page is read: a school's staff list is bounded, and the picker searches
/// what it holds.
final advanceEmployeesProvider = FutureProvider.autoDispose.family<List<EmployeeSalary>, int?>((ref, schoolId) async {
  final repository = ref.read(payrollRepositoryProvider);
  final everyone = <EmployeeSalary>[];
  var page = 1;

  while (true) {
    final response = await repository.salaries(schoolId: schoolId, page: page, perPage: 100);
    everyone.addAll(response.items);
    if (response.currentPage >= response.lastPage) return everyone;
    page++;
  }
});

/// Logs money paid to an employee ahead of their pay (docs/dashboard.md,
/// D4): it comes off their payslip each month, from the month chosen, until
/// it is repaid.
class RecordAdvanceDialog extends ConsumerStatefulWidget {
  const RecordAdvanceDialog({super.key, this.schoolId});

  final int? schoolId;

  @override
  ConsumerState<RecordAdvanceDialog> createState() => _RecordAdvanceDialogState();
}

class _RecordAdvanceDialogState extends ConsumerState<RecordAdvanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _monthly = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  int? _employeeId;
  late DateTime _paidOn = ref.read(schoolClockProvider).today;
  PaymentMode _mode = PaymentMode.cash;

  /// The first month it comes off; null is the month after it was paid.
  DateTime? _startsOn;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _monthly.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  DateTime get _defaultStart => DateTime(_paidOn.year, _paidOn.month + 1);

  /// The months recovery may start in: the month it was paid, and the year
  /// after it.
  List<DateTime> get _months => [for (var i = 0; i < 13; i++) DateTime(_paidOn.year, _paidOn.month + i)];

  static final _moneyPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  String? _moneyProblem(String? value, String what) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the $what.';
    if (!_moneyPattern.hasMatch(text) || double.parse(text) <= 0) return 'Enter an amount like 2500 or 2500.50.';

    return null;
  }

  Future<void> _pickDate() async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(today.year - 2),
      // An advance not yet paid is not recorded as paid.
      lastDate: today,
      helpText: 'Paid on',
    );

    if (picked != null) {
      setState(() {
        _paidOn = picked;
        // A start month before the new payment month is no longer allowed.
        if (_startsOn != null && _startsOn!.isBefore(DateTime(picked.year, picked.month))) _startsOn = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(advanceListNotifierProvider.notifier)
          .record(
            staffProfileId: _employeeId!,
            amount: _amount.text.trim(),
            paidOn: _paidOn,
            mode: _mode,
            reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            monthlyRecovery: _monthly.text.trim(),
            recoveryStarts: _startsOn,
            reason: _reason.text.trim(),
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = error is Failure ? error.message : 'The advance could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(advanceEmployeesProvider(widget.schoolId));
    final start = _startsOn ?? _defaultStart;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Record an advance'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                employees.when(
                  data: (list) => SearchableDropdown<int>(
                    key: const Key('advance-employee'),
                    initialValue: _employeeId,
                    decoration: const InputDecoration(labelText: 'Employee'),
                    items: [
                      for (final employee in list)
                        DropdownMenuItem(
                          value: employee.staffProfileId,
                          child: Text('${employee.name} · ${employee.employeeId}'),
                        ),
                    ],
                    onChanged: (id) => setState(() => _employeeId = id),
                    validator: (id) => id == null ? 'Choose the employee.' : null,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(
                    error is Failure ? error.message : 'The staff list could not be loaded.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('advance-amount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount paid'),
                        validator: (value) => _moneyProblem(value, 'amount'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: const Key('advance-monthly'),
                        controller: _monthly,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Taken back each month'),
                        validator: (value) {
                          final problem = _moneyProblem(value, 'monthly amount');
                          if (problem != null) return problem;
                          final whole = double.tryParse(_amount.text.trim());
                          if (whole != null && double.parse(value!.trim()) > whole) {
                            return 'Not more than the advance.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('advance-paid-on'),
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text('Paid on ${formatDate(_paidOn)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<PaymentMode>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Paid by'),
                        items: [
                          for (final mode in PaymentMode.values) DropdownMenuItem(value: mode, child: Text(mode.label)),
                        ],
                        onChanged: (mode) => setState(() => _mode = mode ?? _mode),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _reference,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                    hintText: 'e.g. cheque or UPI number',
                  ),
                ),
                DropdownButtonFormField<DateTime>(
                  key: const Key('advance-starts'),
                  initialValue: start,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'First payslip it comes off'),
                  items: [
                    for (final month in _months) DropdownMenuItem(value: month, child: Text(monthYearLabel(month))),
                  ],
                  onChanged: (month) => setState(() => _startsOn = month),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('advance-reason'),
                  controller: _reason,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'What it is for', hintText: 'e.g. Medical emergency'),
                  validator: (value) => (value ?? '').trim().length < 3 ? 'Say what the advance is for.' : null,
                ),
                Text(
                  'It comes off their payslip each month from ${monthYearLabel(start)} until it is repaid. A draft '
                  'payroll picks it up when it is regenerated.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const Key('advance-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('advance-save'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Record advance'),
        ),
      ],
    );
  }
}

/// "December 2026".
String monthYearLabel(DateTime month) => DateFormat('MMMM y').format(month);
