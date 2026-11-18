import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/advances_notifier.dart';
import '../data/models/staff_advance.dart';
import 'record_advance_dialog.dart';

/// Advances paid to staff and how far each is repaid (docs/dashboard.md,
/// D4). Recovery happens on the payslips; this is where the money paid out
/// is logged and followed.
class AdvancesTab extends ConsumerWidget {
  const AdvancesTab({super.key, required this.canManage, this.schoolId});

  final bool canManage;
  final int? schoolId;

  Future<void> _record(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecordAdvanceDialog(schoolId: schoolId),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Advance recorded. It comes off the payslips from the month chosen.')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(advanceListNotifierProvider);
    final notifier = ref.read(advanceListNotifierProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (label, status) in [
                ('Being recovered', StaffAdvanceStatus.active),
                ('Repaid', StaffAdvanceStatus.repaid),
                ('Cancelled', StaffAdvanceStatus.cancelled),
                ('All', null),
              ])
                ChoiceChip(
                  key: Key('advance-filter-${status?.apiValue ?? 'all'}'),
                  label: Text(label),
                  selected: notifier.status == status,
                  onSelected: (_) => notifier.setStatus(status),
                ),
              if (canManage)
                FilledButton.icon(
                  key: const Key('advance-record'),
                  onPressed: () => _record(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Record advance'),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncValueView<PagedList<StaffAdvance>>(
            value: state,
            onRetry: notifier.refresh,
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No advances here.')),
            data: (context, page) => Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _AdvanceCard(advance: page.items[index], canManage: canManage),
                  ),
                ),
                PaginationControls(
                  currentPage: page.currentPage,
                  lastPage: page.lastPage,
                  total: page.total,
                  perPage: page.perPage,
                  onPageChanged: notifier.goToPage,
                  onPerPageChanged: notifier.setPerPage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdvanceCard extends ConsumerWidget {
  const _AdvanceCard({required this.advance, required this.canManage});

  final StaffAdvance advance;
  final bool canManage;

  String _money(String amount) => formatCurrency(double.parse(amount), advance.currencyCode);

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _CancelAdvanceDialog());
    if (reason == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(advanceListNotifierProvider.notifier).cancel(advance, reason: reason);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Advance cancelled.')));
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(error is Failure ? error.message : 'The advance could not be cancelled.')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final pending = double.tryParse(advance.pending) ?? 0;

    return Card(
      key: Key('advance-${advance.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  '${advance.employeeName}${advance.employeeCode == null ? '' : ' · ${advance.employeeCode}'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                StatusBadge(
                  label: advance.status.label,
                  tone: switch (advance.status) {
                    StaffAdvanceStatus.active => BadgeTone.info,
                    StaffAdvanceStatus.repaid => BadgeTone.success,
                    StaffAdvanceStatus.cancelled => BadgeTone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_money(advance.amount)} paid ${formatDate(advance.paidOn)} by ${advance.paymentModeLabel}'
              ' - ${advance.reason}',
              style: muted,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: advance.progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 6),
            Text(
              advance.status == StaffAdvanceStatus.cancelled
                  ? 'Cancelled${advance.cancelReason == null ? '' : ': ${advance.cancelReason}'}'
                  : '${_money(advance.recovered)} recovered, ${_money(advance.remaining)} left · '
                        '${_money(advance.monthlyRecovery)} a month from ${advance.recoveryStartsLabel}',
              key: Key('advance-progress-${advance.id}'),
            ),
            if (pending > 0)
              Text('${_money(advance.pending)} more on a draft payroll, counted once it is finalized.', style: muted),
            if (canManage && advance.canCancel)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('advance-cancel-${advance.id}'),
                  onPressed: () => _cancel(context, ref),
                  child: const Text('Cancel advance'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CancelAdvanceDialog extends StatefulWidget {
  const _CancelAdvanceDialog();

  @override
  State<_CancelAdvanceDialog> createState() => _CancelAdvanceDialogState();
}

class _CancelAdvanceDialogState extends State<_CancelAdvanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel this advance?'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'It stays on record, marked cancelled, and no payslip takes it back. Only possible while nothing '
                'has been recovered.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('advance-cancel-reason'),
                controller: _reason,
                autofocus: true,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Entered twice'),
                validator: (value) => (value ?? '').trim().length < 3 ? 'Say why it is being cancelled.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep it')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.of(context).pop(_reason.text.trim());
          },
          child: const Text('Cancel advance'),
        ),
      ],
    );
  }
}
