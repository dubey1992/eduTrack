import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_format.dart';
import '../../application/fees_lock_provider.dart';
import '../../data/fee_repository.dart';
import '../../data/models/fees_lock.dart';

/// Opens the date lock (docs/dashboard.md, D3) for [schoolId] - the school
/// picked by whoever picks one, else null for their own.
Future<void> showFeesLockDialog(BuildContext context, {int? schoolId}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FeesLockDialog(schoolId: schoolId),
  );
}

/// The fee books' date lock: closes every day up to a date to receipts,
/// cancellations, discounts, waivers, late fines and refunds. Attendance,
/// exams and everything else carry on as usual.
class FeesLockDialog extends ConsumerWidget {
  const FeesLockDialog({super.key, this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(feesLockProvider(schoolId))
        .when(
          data: (lock) => _LockForm(lock: lock, schoolId: schoolId),
          loading: () => const AlertDialog(
            title: Text('Date lock'),
            content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          ),
          error: (error, _) => AlertDialog(
            title: const Text('Date lock'),
            content: Text(error is Failure ? error.message : 'The date lock could not be loaded.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              FilledButton(onPressed: () => ref.invalidate(feesLockProvider(schoolId)), child: const Text('Retry')),
            ],
          ),
        );
  }
}

/// "Books closed up to 07/14/2026" above a fee screen, with the way to move
/// it for whoever may. Nothing at all when nothing is locked and the person
/// cannot lock, or when the lock cannot be read (a school not yet picked).
class FeesLockLine extends ConsumerWidget {
  const FeesLockLine({super.key, this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(feesLockProvider(schoolId)).value;
    if (lock == null || (!lock.isLocked && !lock.canChange)) return const SizedBox.shrink();

    final colours = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Wrap(
        key: const Key('fees-lock-line'),
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(lock.isLocked ? Icons.lock_outline : Icons.lock_open_outlined, size: 18, color: colours.muted),
          Text(
            lock.isLocked ? 'Fee books closed up to ${formatDate(lock.lockedUntil!)}' : 'No date lock on the fee books',
            style: TextStyle(color: colours.muted),
          ),
          TextButton(
            onPressed: () => showFeesLockDialog(context, schoolId: schoolId),
            child: Text(lock.canChange ? 'Change' : 'Details'),
          ),
        ],
      ),
    );
  }
}

class _LockForm extends ConsumerStatefulWidget {
  const _LockForm({required this.lock, required this.schoolId});

  final FeesLock lock;
  final int? schoolId;

  @override
  ConsumerState<_LockForm> createState() => _LockFormState();
}

class _LockFormState extends ConsumerState<_LockForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late DateTime? _until = widget.lock.lockedUntil ?? widget.lock.today.subtract(const Duration(days: 1));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _reopens => widget.lock.reopens(_until);

  Future<void> _pick() async {
    final lock = widget.lock;
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? lock.today,
      firstDate: DateTime(lock.today.year - 3),
      // Never a day still to come: the lock closes days that are over.
      lastDate: lock.today,
      helpText: 'Close the books up to',
    );

    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _save(DateTime? until) async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(feeRepositoryProvider).setBooksLock(until: until, reason: _reason.text, schoolId: widget.schoolId);
      ref.invalidate(feesLockProvider(widget.schoolId));

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            until == null ? 'The date lock is cleared.' : 'The fee books are closed up to ${formatDate(until)}.',
          ),
        ),
      );
    } catch (error) {
      setState(() => _error = error is Failure ? error.message : 'The date lock could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    final scheme = Theme.of(context).colorScheme;
    final colours = context.appColors;
    final until = _until;

    return AlertDialog(
      title: const Text('Date lock'),
      content: SizedBox(
        width: 460,
        // Scrolls on a short screen rather than running off its bottom.
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: const Key('fees-lock-state'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: lock.isLocked ? colours.warningContainer : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    lock.isLocked
                        ? 'The fee books are closed up to ${formatDate(lock.lockedUntil!)}.'
                        : 'Nothing is locked: any date can still be recorded.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: lock.isLocked ? colours.onWarningContainer : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Locking a date stops any receipt, cancellation, discount, waiver, late fine or refund dated on or '
                  'before it. Attendance, exams and everything else are not affected.',
                ),
                if (lock.canChange) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('fees-lock-date'),
                    onPressed: _saving ? null : _pick,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(until == null ? 'Pick a date' : 'Close the books up to ${formatDate(until)}'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('fees-lock-reason'),
                    controller: _reason,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _reopens ? 'Reason for reopening (required)' : 'Reason (optional)',
                      hintText: 'e.g. A receipt was entered on the wrong day',
                    ),
                    validator: (value) =>
                        _reopens && (value ?? '').trim().length < 3 ? 'Say why closed days are being reopened.' : null,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    'Only a School Admin or an Accountant can move the date lock.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const Key('fees-lock-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        if (lock.canChange && lock.isLocked)
          TextButton(
            key: const Key('fees-lock-clear'),
            onPressed: _saving
                ? null
                : () {
                    setState(() => _until = null);
                    _save(null);
                  },
            child: const Text('Clear lock'),
          ),
        if (lock.canChange)
          FilledButton(
            key: const Key('fees-lock-save'),
            onPressed: _saving || until == null || until == lock.lockedUntil ? null : () => _save(until),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save lock'),
          ),
      ],
    );
  }
}
