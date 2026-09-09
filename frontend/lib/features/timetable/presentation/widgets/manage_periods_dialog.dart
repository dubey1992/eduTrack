import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../application/period_list_notifier.dart';
import '../../data/models/period.dart';

/// CRUD for a school's period timings - the "Period Management" half of
/// the prototype's "Timetable & Period Management" screen. Periods are
/// configured once per school and reused across every class section's
/// grid, so this is deliberately its own dialog rather than inline in the
/// grid itself.
class ManagePeriodsDialog extends ConsumerWidget {
  const ManagePeriodsDialog({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsState = ref.watch(periodListNotifierProvider(schoolId));

    return AlertDialog(
      title: const Text('Manage Periods'),
      content: SizedBox(
        width: 420,
        child: AsyncValueView<List<Period>>(
          value: periodsState,
          onRetry: () => ref.read(periodListNotifierProvider(schoolId).notifier).refresh(),
          isEmpty: (periods) => periods.isEmpty,
          emptyBuilder: (context) =>
              const Padding(padding: EdgeInsets.all(16), child: Text('No periods configured yet.')),
          data: (context, periods) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final period in periods) _PeriodRow(schoolId: schoolId, period: period)],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _EditPeriodDialog(schoolId: schoolId),
          ),
          child: const Text('Add Period'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

class _PeriodRow extends ConsumerWidget {
  const _PeriodRow({required this.schoolId, required this.period});

  final int? schoolId;
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      title: Text('Period ${period.periodNumber}'),
      subtitle: Text('${period.startTime} - ${period.endTime}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _EditPeriodDialog(schoolId: schoolId, period: period),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete',
            onPressed: () async {
              try {
                await ref.read(periodListNotifierProvider(schoolId).notifier).delete(period);
              } catch (error) {
                if (context.mounted) {
                  final failure = error is Failure ? error : Failure.unknown(error.toString());
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _EditPeriodDialog extends ConsumerStatefulWidget {
  const _EditPeriodDialog({required this.schoolId, this.period});

  final int? schoolId;
  final Period? period;

  @override
  ConsumerState<_EditPeriodDialog> createState() => _EditPeriodDialogState();
}

class _EditPeriodDialogState extends ConsumerState<_EditPeriodDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _numberController = TextEditingController(text: widget.period?.periodNumber.toString() ?? '');
  TimeOfDay? _startTime = _parse(null);
  TimeOfDay? _endTime = _parse(null);

  bool _isSubmitting = false;
  String? _errorMessage;

  static TimeOfDay? _parse(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  void initState() {
    super.initState();
    _startTime = _parse(widget.period?.startTime);
    _endTime = _parse(widget.period?.endTime);
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  String _format(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate() || _startTime == null || _endTime == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(periodListNotifierProvider(widget.schoolId).notifier);
      if (widget.period == null) {
        await notifier.create(
          periodNumber: int.parse(_numberController.text),
          startTime: _format(_startTime!),
          endTime: _format(_endTime!),
        );
      } else {
        await notifier.editPeriod(
          widget.period!,
          periodNumber: int.parse(_numberController.text),
          startTime: _format(_startTime!),
          endTime: _format(_endTime!),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.period == null ? 'Add Period' : 'Edit Period'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Period number'),
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _pickTime(isStart: true),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Start time'),
                  child: Text(_startTime == null ? 'Select' : _format(_startTime!)),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _pickTime(isStart: false),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'End time'),
                  child: Text(_endTime == null ? 'Select' : _format(_endTime!)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
