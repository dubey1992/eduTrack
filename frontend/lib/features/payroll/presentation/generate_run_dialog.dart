import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/payroll_notifiers.dart';
import '../data/models/payroll.dart';

/// Starts a month's payroll as a draft. The month cannot be one that has not
/// started; somebody spanning several schools names which one.
///
/// Closes with the generated run, so the screen can open it straight away.
class GenerateRunDialog extends ConsumerStatefulWidget {
  const GenerateRunDialog({super.key});

  @override
  ConsumerState<GenerateRunDialog> createState() => _GenerateRunDialogState();
}

class _GenerateRunDialogState extends ConsumerState<GenerateRunDialog> {
  late final DateTime _today = ref.read(schoolClockProvider).today;
  late int _year = _today.year;
  late int _month = _today.month;
  int? _schoolId;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final picksSchool = ref.read(authNotifierProvider).value?.picksSchool ?? false;

    if (picksSchool && _schoolId == null) {
      setState(() => _error = 'Pick the school to run payroll for.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final PayrollRun run = await ref
          .read(payrollRunListNotifierProvider.notifier)
          .generate(year: _year, month: _month, schoolId: picksSchool ? _schoolId : null);
      if (mounted) Navigator.of(context).pop(run);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      final fieldMessages = failure.validationErrors.values.expand((messages) => messages).toList();
      setState(() => _error = fieldMessages.isEmpty ? failure.message : fieldMessages.join('\n'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;
    final lastMonthThisYear = _year == _today.year ? _today.month : 12;

    return AlertDialog(
      title: const Text('Run Payroll'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (picksSchool) ...[
              SchoolPicker(selected: _schoolId, onChanged: (id) => setState(() => _schoolId = id)),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: [
                      for (var month = 1; month <= lastMonthThisYear; month++)
                        DropdownMenuItem(value: month, child: Text(DateFormat.MMMM().format(DateTime(2000, month)))),
                    ],
                    onChanged: (month) => setState(() => _month = month!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (var year = _today.year; year >= _today.year - 5; year--)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (year) => setState(() {
                      _year = year!;
                      if (_year == _today.year && _month > _today.month) _month = _today.month;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A draft is built from current salaries and the staff register. You can adjust it and regenerate it '
              'until it is finalized.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Generate Draft'),
        ),
      ],
    );
  }
}
