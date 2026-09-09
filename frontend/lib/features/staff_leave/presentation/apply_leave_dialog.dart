import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../application/staff_leave_list_notifier.dart';
import '../data/models/leave_status.dart';
import '../data/models/leave_type.dart';

/// Self-service "Apply Leave" form - the staff_profile_id it applies for is
/// always the signed-in actor's own, resolved server-side (see
/// StaffLeaveController::store), so there's no staff picker here.
class ApplyLeaveDialog extends ConsumerStatefulWidget {
  const ApplyLeaveDialog({super.key});

  @override
  ConsumerState<ApplyLeaveDialog> createState() => _ApplyLeaveDialogState();
}

class _ApplyLeaveDialogState extends ConsumerState<ApplyLeaveDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  LeaveType _leaveType = LeaveType.casual;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final created = await ref
          .read(staffLeaveListNotifierProvider.notifier)
          .applyLeave(
            leaveType: _leaveType,
            startDate: DateFormat('yyyy-MM-dd').format(_startDate),
            endDate: DateFormat('yyyy-MM-dd').format(_endDate),
            reason: _reasonController.text.trim(),
          );
      if (mounted) {
        // A School Admin's own request is auto-approved immediately (see
        // the backend's StaffLeaveService::apply()) - say so, rather than
        // "submitted", which would read as still awaiting someone's review.
        final message = created.status == LeaveStatus.approved
            ? 'Leave request approved automatically.'
            : 'Leave request submitted.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).pop();
      }
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
      title: const Text('Apply Leave'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<LeaveType>(
                  initialValue: _leaveType,
                  decoration: const InputDecoration(labelText: 'Leave type'),
                  items: [for (final type in LeaveType.values) DropdownMenuItem(value: type, child: Text(type.label))],
                  onChanged: (value) => setState(() => _leaveType = value!),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickStartDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'From'),
                    child: Text(DateFormat.yMMMd().format(_startDate)),
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickEndDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'To'),
                    child: Text(DateFormat.yMMMd().format(_endDate)),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  maxLines: 3,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Reason is required' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit Request'),
        ),
      ],
    );
  }
}
