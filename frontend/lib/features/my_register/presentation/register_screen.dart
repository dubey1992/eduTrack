import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../attendance/data/models/attendance_status.dart';
import '../application/register_queue.dart';
import '../application/register_sheet_notifier.dart';

/// Taking a class register on the phone (docs/teacher-app.md, T2): the class
/// as a list of large rows, Present / Absent / Leave on each, a running
/// tally, and one Submit that asks first. Without signal the register is
/// saved on the phone and sent when signal returns.
class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({super.key, required this.registerKey});

  final RegisterKey registerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(registerSheetProvider(registerKey));
    final date = DateTime.parse(registerKey.date);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${registerKey.label} register'),
            Text(
              DateFormat('EEEE, MMMM d').format(date),
              style: TextStyle(fontSize: 13, color: context.appColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AsyncValueView<RegisterSheet>(
              value: sheet,
              onRetry: () => ref.read(registerSheetProvider(registerKey).notifier).reload(),
              data: (context, sheet) => _Sheet(registerKey: registerKey, sheet: sheet),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.registerKey, required this.sheet});

  final RegisterKey registerKey;
  final RegisterSheet sheet;

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  bool _busy = false;
  String? _problem;

  RegisterSheetNotifier get _notifier => ref.read(registerSheetProvider(widget.registerKey).notifier);

  Future<void> _submit() async {
    final sheet = widget.sheet;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('register-confirm'),
        title: const Text('Submit the register?'),
        content: Text(_summary(sheet)),
        actions: [
          TextButton(
            key: const Key('register-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Check again'),
          ),
          FilledButton(
            key: const Key('register-confirm-submit'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _problem = null;
    });
    final outcome = await _notifier.submit();
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (outcome) {
      RegisterMode.submitted => 'Register submitted.',
      RegisterMode.waiting => 'No signal: the register is saved on this phone and sent when there is.',
      _ => null,
    };
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveCorrection() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await _notifier.saveCorrection();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Register corrected.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(
          () => _problem = failure.code == 'NETWORK_ERROR'
              ? 'A correction needs a connection, because parents may already have been told. Try again with signal.'
              : failure.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet;
    final colors = context.appColors;

    if (sheet.mode == RegisterMode.closed) {
      return _Centered(
        key: const Key('register-closed'),
        icon: Icons.event_busy_outlined,
        title: 'Holiday: ${sheet.holidayName}',
        body: 'The school is closed, so there is no register to take.',
      );
    }

    if (sheet.students.isEmpty) {
      return const _Centered(
        key: Key('register-no-students'),
        icon: Icons.group_off_outlined,
        title: 'No students in this class',
        body: 'There is nobody on the class list to mark. Ask the office if that is wrong.',
      );
    }

    return Column(
      children: [
        _Tally(sheet: sheet),
        if (sheet.offline || sheet.mode == RegisterMode.waiting || sheet.refusal != null || _problem != null)
          _Banner(sheet: sheet, problem: _problem),
        Expanded(
          child: ListView.separated(
            key: const Key('register-list'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: sheet.students.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final student = sheet.students[index];
              return _StudentRow(
                student: student,
                mark: sheet.marks[student.id],
                editable: sheet.editable && !_busy,
                onMark: (status) => _notifier.setMark(student.id, status),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: colors.muted.withValues(alpha: 0.2))),
          ),
          child: _Actions(
            sheet: sheet,
            busy: _busy,
            onAllPresent: _notifier.markAllPresent,
            onSubmit: _submit,
            onCorrect: _notifier.startCorrecting,
            onSaveCorrection: _saveCorrection,
          ),
        ),
      ],
    );
  }
}

String _summary(RegisterSheet sheet) {
  final parts = [
    '${sheet.count(AttendanceStatus.present)} present',
    '${sheet.count(AttendanceStatus.absent)} absent',
    if (sheet.count(AttendanceStatus.leave) > 0) '${sheet.count(AttendanceStatus.leave)} on leave',
  ];
  final absent = sheet.count(AttendanceStatus.absent);
  return '${parts.join(', ')}.'
      '${absent > 0 ? ' Parents of absent children are told, as your school has set it up.' : ''}';
}

class _Tally extends StatelessWidget {
  const _Tally({required this.sheet});

  final RegisterSheet sheet;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget chip(String key, String label, int count, Color colour) => Expanded(
      child: Container(
        key: Key('register-tally-$key'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colour),
            ),
            Text(label, style: TextStyle(fontSize: 12, color: colour)),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          chip('present', 'Present', sheet.count(AttendanceStatus.present), colors.success),
          const SizedBox(width: 8),
          chip('absent', 'Absent', sheet.count(AttendanceStatus.absent), colors.danger),
          const SizedBox(width: 8),
          chip('leave', 'Leave', sheet.count(AttendanceStatus.leave), colors.info),
          const SizedBox(width: 8),
          chip('unmarked', 'Not marked', sheet.unmarked, colors.muted),
        ],
      ),
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.sheet, required this.problem});

  final RegisterSheet sheet;
  final String? problem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final sending = ref.watch(registerQueueProvider).sending;

    final (text, background, foreground, key) = problem != null
        ? (problem!, colors.dangerContainer, colors.onDangerContainer, 'register-problem')
        : sheet.refusal != null
        ? ('Not sent: ${sheet.refusal}', colors.dangerContainer, colors.onDangerContainer, 'register-refused')
        : sheet.mode == RegisterMode.waiting
        ? (
            sending
                ? 'Sending the register…'
                : 'Saved on this phone, not yet sent. It goes as soon as there is signal - you can close the app.',
            colors.warningContainer,
            colors.onWarningContainer,
            'register-waiting',
          )
        : (
            'No connection. Take the register as usual: it is saved on this phone and sent when there is signal.',
            colors.infoContainer,
            colors.onInfoContainer,
            'register-offline',
          );

    return Container(
      key: Key(key),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: foreground, height: 1.35)),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.mark, required this.editable, required this.onMark});

  final RegisterStudent student;
  final AttendanceStatus? mark;
  final bool editable;
  final ValueChanged<AttendanceStatus> onMark;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget button(AttendanceStatus status, String letter, Color colour) {
      final chosen = mark == status;
      return Expanded(
        child: SizedBox(
          height: 44,
          child: OutlinedButton(
            key: Key('register-${student.id}-${status.apiValue}'),
            onPressed: editable ? () => onMark(status) : null,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: chosen ? colour : null,
              foregroundColor: chosen ? Colors.white : colour,
              disabledForegroundColor: chosen ? Colors.white : colour.withValues(alpha: 0.4),
              disabledBackgroundColor: chosen ? colour.withValues(alpha: 0.85) : null,
              side: BorderSide(color: colour.withValues(alpha: chosen ? 1 : 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Card(
      key: Key('register-row-${student.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (student.rollNumber != null) ...[
                  Text(
                    student.rollNumber!,
                    style: TextStyle(color: colors.muted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(student.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                button(AttendanceStatus.present, 'Present', colors.success),
                const SizedBox(width: 8),
                button(AttendanceStatus.absent, 'Absent', colors.danger),
                const SizedBox(width: 8),
                button(AttendanceStatus.leave, 'Leave', colors.info),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.sheet,
    required this.busy,
    required this.onAllPresent,
    required this.onSubmit,
    required this.onCorrect,
    required this.onSaveCorrection,
  });

  final RegisterSheet sheet;
  final bool busy;
  final VoidCallback onAllPresent;
  final VoidCallback onSubmit;
  final VoidCallback onCorrect;
  final VoidCallback onSaveCorrection;

  @override
  Widget build(BuildContext context) {
    final spinner = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

    return switch (sheet.mode) {
      RegisterMode.taking => Row(
        children: [
          OutlinedButton(
            key: const Key('register-all-present'),
            onPressed: busy ? null : onAllPresent,
            child: const Text('All present'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('register-submit'),
                onPressed: busy || !sheet.complete ? null : onSubmit,
                child: busy ? spinner : Text(sheet.complete ? 'Submit' : 'Mark everyone (${sheet.unmarked} left)'),
              ),
            ),
          ),
        ],
      ),
      RegisterMode.correcting => SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          key: const Key('register-save-correction'),
          onPressed: busy ? null : onSaveCorrection,
          child: busy ? spinner : const Text('Save correction'),
        ),
      ),
      RegisterMode.submitted => Row(
        children: [
          Icon(Icons.check_circle, color: context.appColors.success),
          const SizedBox(width: 8),
          const Expanded(child: Text('Submitted.', key: Key('register-submitted'))),
          TextButton(key: const Key('register-correct'), onPressed: onCorrect, child: const Text('Correct')),
        ],
      ),
      RegisterMode.waiting => const Row(
        children: [
          Icon(Icons.schedule_send_outlined),
          SizedBox(width: 8),
          Expanded(child: Text('Waiting for signal to send.')),
        ],
      ),
      RegisterMode.closed => const SizedBox.shrink(),
    };
  }
}

class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.muted),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(color: colors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
