import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../application/fee_setup_providers.dart';
import '../../data/models/fee_head.dart';
import 'fee_head_dialog.dart';

/// The kinds of fee a school charges. Transport is always there, for bus
/// route fees, and cannot be changed.
class FeeHeadsTab extends ConsumerWidget {
  const FeeHeadsTab({super.key, required this.schoolId, required this.canManage});

  final int? schoolId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<FeeHead>>(
      value: ref.watch(feeHeadsProvider(schoolId)),
      onRetry: () => ref.invalidate(feeHeadsProvider(schoolId)),
      data: (context, heads) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'The kinds of fee the school charges. Set the amounts under Class Fees and Bus Route Fees.',
                style: TextStyle(color: context.appColors.muted),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => showFeeHeadDialog(context, schoolId: schoolId),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Fee Type'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final head in heads) ...[
            _HeadCard(head: head, canManage: canManage, schoolId: schoolId),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _HeadCard extends ConsumerStatefulWidget {
  const _HeadCard({required this.head, required this.canManage, required this.schoolId});

  final FeeHead head;
  final bool canManage;
  final int? schoolId;

  @override
  ConsumerState<_HeadCard> createState() => _HeadCardState();
}

class _HeadCardState extends ConsumerState<_HeadCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      final message = error is Failure ? error.message : 'That did not work. Please try again.';
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retire() async {
    final head = widget.head;
    final confirmed = await confirmDialog(
      context,
      title: 'Retire "${head.name}"?',
      message:
          'It stays on the ${head.structuresCount} fee(s) already set up with it, but cannot be chosen for a new '
          'one. You can restore it later.',
      confirmLabel: 'Retire',
    );
    if (!confirmed || !mounted) return;

    await _run(
      () => ref.read(feeSetupActionsProvider).setHeadActive(head.id, active: false),
      '"${head.name}" retired.',
    );
  }

  Future<void> _delete() async {
    final head = widget.head;
    final confirmed = await confirmDialog(
      context,
      title: 'Delete "${head.name}"?',
      message: 'No fee uses it, so nothing else changes.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(feeSetupActionsProvider).deleteHead(head.id), '"${head.name}" deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.head;
    final muted = context.appColors.muted;
    final editable = widget.canManage && !head.isTransport;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 10,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(head.name, style: Theme.of(context).textTheme.titleMedium),
                    if (head.isTransport) const StatusBadge(label: 'Bus routes', tone: BadgeTone.info),
                    if (!head.isActive) const StatusBadge(label: 'Retired', tone: BadgeTone.neutral),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  head.isTransport
                      ? 'Charged by bus route. Always available.'
                      : head.structuresCount == 0
                      ? 'Not used by any fee yet.'
                      : 'Used by ${head.structuresCount} fee${head.structuresCount == 1 ? '' : 's'}.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
            if (editable)
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  TextButton(
                    onPressed: _busy ? null : () => showFeeHeadDialog(context, schoolId: widget.schoolId, head: head),
                    child: const Text('Rename'),
                  ),
                  if (head.isActive)
                    TextButton(onPressed: _busy ? null : _retire, child: const Text('Retire'))
                  else
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => ref.read(feeSetupActionsProvider).setHeadActive(head.id, active: true),
                              '"${head.name}" restored.',
                            ),
                      child: const Text('Restore'),
                    ),
                  if (head.structuresCount == 0)
                    IconButton(
                      onPressed: _busy ? null : _delete,
                      tooltip: 'Delete fee type',
                      icon: Icon(Icons.delete_outline, color: context.appColors.danger),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
