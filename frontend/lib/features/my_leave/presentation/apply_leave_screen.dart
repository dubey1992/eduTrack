import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../staff_leave/data/models/leave_status.dart';
import '../../staff_leave/data/models/leave_type.dart';
import '../application/my_leave_notifier.dart';

/// Asking for leave from the phone - a whole screen rather than the web's
/// dialog, so the keyboard has room for the reason.
///
/// The form checks what it can see (a reason, an end not before the start,
/// a half day being one date); notice, overlapping requests and days the
/// school is closed are the server's rules, and its sentence is shown as is.
class ApplyLeaveScreen extends ConsumerStatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  ConsumerState<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends ConsumerState<ApplyLeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  LeaveType _type = LeaveType.casual;
  late DateTime _start;
  late DateTime _end;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = ref.read(schoolClockProvider).today;
    _end = _start;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: start ? today : _start,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      if (start) {
        _start = picked;
        // An end before the new start is no range at all; move it along.
        if (_end.isBefore(_start) || _type == LeaveType.halfDay) _end = _start;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final wire = DateFormat('yyyy-MM-dd');

    try {
      final created = await ref
          .read(myLeaveProvider.notifier)
          .apply(
            leaveType: _type,
            startDate: wire.format(_start),
            endDate: wire.format(_type == LeaveType.halfDay ? _start : _end),
            reason: _reasonController.text.trim(),
          );
      if (!mounted) return;
      // A School Admin's own request approves itself (StaffLeaveService) -
      // "submitted" would read as still waiting for somebody.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created.status == LeaveStatus.approved
                ? 'Leave approved automatically.'
                : 'Leave requested. You will see here when it is decided.',
          ),
        ),
      );
      context.pop();
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final halfDay = _type == LeaveType.halfDay;

    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      key: const Key('apply-leave-error'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(10)),
                      child: Text(_error!, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<LeaveType>(
                    key: const Key('apply-leave-type'),
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Leave type'),
                    items: [
                      for (final type in LeaveType.values) DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() {
                            _type = value!;
                            if (_type == LeaveType.halfDay) _end = _start;
                          }),
                  ),
                  const SizedBox(height: 14),
                  _DateField(
                    key: const Key('apply-leave-start'),
                    label: halfDay ? 'Date' : 'From',
                    date: _start,
                    onTap: _isSubmitting ? null : () => _pick(start: true),
                  ),
                  if (!halfDay) ...[
                    const SizedBox(height: 14),
                    _DateField(
                      key: const Key('apply-leave-end'),
                      label: 'To',
                      date: _end,
                      onTap: _isSubmitting ? null : () => _pick(start: false),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('apply-leave-reason'),
                    controller: _reasonController,
                    enabled: !_isSubmitting,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Reason', alignLabelWithHint: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Say why you need the leave.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    halfDay
                        ? 'Half-day leave: you check in for the half you work, and the day counts as a half day.'
                        : 'Weekends and holidays inside the dates are not counted as leave.',
                    style: TextStyle(fontSize: 13, color: colors.muted, height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: const Key('apply-leave-submit'),
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : const Text('Send request'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({super.key, required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
        child: Text('${DateFormat('EEE').format(date)}, ${formatDate(date)}'),
      ),
    );
  }
}
