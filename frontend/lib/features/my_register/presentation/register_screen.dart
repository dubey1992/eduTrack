import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../absence_notes/presentation/absence_note_chip.dart';
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
            Text(context.l10n.staffRegisterTitle(registerKey.label)),
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

  /// Name or roll number typed into the search box; empty is the whole class.
  String _query = '';

  RegisterSheetNotifier get _notifier => ref.read(registerSheetProvider(widget.registerKey).notifier);

  Future<void> _submit() async {
    final sheet = widget.sheet;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('register-confirm'),
        title: Text(l10n.staffSubmitRegisterQ),
        content: Text(_summary(l10n, sheet)),
        actions: [
          TextButton(
            key: const Key('register-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.staffCheckAgain),
          ),
          FilledButton(
            key: const Key('register-confirm-submit'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.staffSubmit),
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
      RegisterMode.submitted => l10n.staffRegisterSubmitted,
      RegisterMode.waiting => l10n.staffRegisterSavedNoSignal,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.staffRegisterCorrected)));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(
          () => _problem = failure.code == 'NETWORK_ERROR'
              ? context.l10n.staffCorrectionNeedsConnection
              : failure.localizedMessage(context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _list(RegisterSheet sheet, AppColors colors) {
    final l10n = context.l10n;
    final shown = [
      for (final student in sheet.students)
        if (matchesRegisterSearch(student, _query)) student,
    ];
    if (shown.isEmpty) {
      return Center(
        key: const Key('register-search-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.staffNobodyMatches(_query.trim()),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted),
          ),
        ),
      );
    }

    final editable = sheet.editable && !_busy;

    return ListView.separated(
      key: const Key('register-list'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final student = shown[index];
        final row = _StudentRow(
          student: student,
          mark: sheet.marks[student.id],
          editable: editable,
          onMark: (status) => _notifier.setMark(student.id, status),
        );
        if (!editable) return row;

        // A swipe marks and springs back - the row never leaves the list.
        return Dismissible(
          key: Key('register-swipe-${student.id}'),
          confirmDismiss: (direction) async {
            _notifier.setMark(
              student.id,
              direction == DismissDirection.startToEnd ? AttendanceStatus.present : AttendanceStatus.absent,
            );
            return false;
          },
          background: _SwipeHint(colour: colors.success, label: l10n.staffPresent, alignment: Alignment.centerLeft),
          secondaryBackground: _SwipeHint(
            colour: colors.danger,
            label: l10n.staffAbsent,
            alignment: Alignment.centerRight,
          ),
          child: row,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet;
    final colors = context.appColors;
    final l10n = context.l10n;

    if (sheet.mode == RegisterMode.closed) {
      return _Centered(
        key: const Key('register-closed'),
        icon: Icons.event_busy_outlined,
        title: l10n.staffHolidayNamed('${sheet.holidayName}'),
        body: l10n.staffClosedNoRegister,
      );
    }

    if (sheet.students.isEmpty) {
      return _Centered(
        key: const Key('register-no-students'),
        icon: Icons.group_off_outlined,
        title: l10n.staffNoStudentsInClass,
        body: l10n.staffNoStudentsInClassBody,
      );
    }

    return Column(
      children: [
        _Tally(sheet: sheet),
        if (sheet.offline || sheet.mode == RegisterMode.waiting || sheet.refusal != null || _problem != null)
          _Banner(sheet: sheet, problem: _problem),
        if (sheet.mode == RegisterMode.taking)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              l10n.staffRegisterByException,
              key: const Key('register-by-exception'),
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            key: const Key('register-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.staffFindByNameOrRoll,
            ),
          ),
        ),
        Expanded(child: _list(sheet, colors)),
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

/// Whether [student] is who the teacher is looking for: part of the name,
/// or the roll number itself.
bool matchesRegisterSearch(RegisterStudent student, String query) {
  final asked = query.trim().toLowerCase();
  if (asked.isEmpty) return true;

  return student.name.toLowerCase().contains(asked) || (student.rollNumber?.toLowerCase() == asked);
}

String _summary(AppLocalizations l10n, RegisterSheet sheet) {
  final parts = [
    l10n.staffCountPresent(sheet.count(AttendanceStatus.present)),
    l10n.staffCountAbsent(sheet.count(AttendanceStatus.absent)),
    if (sheet.count(AttendanceStatus.leave) > 0) l10n.staffCountOnLeave(sheet.count(AttendanceStatus.leave)),
  ];
  final absent = sheet.count(AttendanceStatus.absent);
  return '${l10n.staffSentence(parts.join(', '))}'
      '${absent > 0 ? ' ${l10n.staffParentsAreTold}' : ''}';
}

class _Tally extends StatelessWidget {
  const _Tally({required this.sheet});

  final RegisterSheet sheet;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

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
          chip('present', l10n.staffPresent, sheet.count(AttendanceStatus.present), colors.success),
          const SizedBox(width: 8),
          chip('absent', l10n.staffAbsent, sheet.count(AttendanceStatus.absent), colors.danger),
          const SizedBox(width: 8),
          chip('leave', l10n.staffNavLeave, sheet.count(AttendanceStatus.leave), colors.info),
          const SizedBox(width: 8),
          chip('unmarked', l10n.staffNotMarked, sheet.unmarked, colors.muted),
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
    final l10n = context.l10n;

    final (text, background, foreground, key) = problem != null
        ? (problem!, colors.dangerContainer, colors.onDangerContainer, 'register-problem')
        : sheet.refusal != null
        // The reason, then what to do about it (docs/mobile-apps-review.md,
        // 2.5): the marks below start again, so taking them again is the retry.
        ? (
            l10n.staffRegisterRefused('${sheet.refusal}'),
            colors.dangerContainer,
            colors.onDangerContainer,
            'register-refused',
          )
        : sheet.mode == RegisterMode.waiting
        ? (
            sending ? l10n.staffSendingRegister : l10n.staffRegisterWaiting,
            colors.warningContainer,
            colors.onWarningContainer,
            'register-waiting',
          )
        : (l10n.staffRegisterOffline, colors.infoContainer, colors.onInfoContainer, 'register-offline');

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
    final l10n = context.l10n;

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
                // The photo, or the initials (docs/student-photos.md, D4).
                UserAvatar(photoUrl: student.photoUrl, name: student.name, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(student.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (student.absenceNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AbsenceNoteChip(note: student.absenceNote!, studentName: student.name),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                button(AttendanceStatus.present, l10n.staffPresent, colors.success),
                const SizedBox(width: 8),
                button(AttendanceStatus.absent, l10n.staffAbsent, colors.danger),
                const SizedBox(width: 8),
                button(AttendanceStatus.leave, l10n.staffNavLeave, colors.info),
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
    final l10n = context.l10n;

    return switch (sheet.mode) {
      RegisterMode.taking => Row(
        children: [
          OutlinedButton(
            key: const Key('register-all-present'),
            onPressed: busy ? null : onAllPresent,
            child: Text(l10n.staffAllPresent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('register-submit'),
                onPressed: busy || !sheet.complete ? null : onSubmit,
                child: busy
                    ? spinner
                    : Text(sheet.complete ? l10n.staffSubmit : l10n.staffMarkEveryone(sheet.unmarked)),
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
          child: busy ? spinner : Text(l10n.staffSaveCorrection),
        ),
      ),
      RegisterMode.submitted => Row(
        children: [
          Icon(Icons.check_circle, color: context.appColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.staffSubmittedDot, key: const Key('register-submitted'))),
          TextButton(key: const Key('register-correct'), onPressed: onCorrect, child: Text(l10n.staffCorrect)),
        ],
      ),
      RegisterMode.waiting => Row(
        children: [
          const Icon(Icons.schedule_send_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.staffWaitingForSignal)),
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

/// What a swipe will do, shown under the row as it moves.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.colour, required this.label, required this.alignment});

  final Color colour;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: colour.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(color: colour, fontWeight: FontWeight.w800),
      ),
    );
  }
}
