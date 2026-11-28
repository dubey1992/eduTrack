import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/dialog_message.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../data/offline_fee_payment.dart';
import '../data/offline_fees_repository.dart';

typedef OfflinePaymentsQuery = ({OfflineFeeStatus? status, int? schoolId, int page, int perPage});

final offlinePaymentsProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<OfflineFeePayment>, OfflinePaymentsQuery>(
      (ref, query) => ref
          .watch(offlineFeesRepositoryProvider)
          .list(status: query.status, schoolId: query.schoolId, page: query.page, perPage: query.perPage),
    );

/// Who settles a payment that could not become a receipt (decided 2026-11-28).
const settlers = {UserRole.schoolAdmin, UserRole.groupAdmin, UserRole.accountant};

/// Fees taken while the internet was down (docs/offline-web.md, O4): each
/// with its provisional number and what became of it. A payment whose dues
/// were paid meanwhile, or whose day's books were closed, waits here to be
/// kept on the student's account or recorded as handed back.
class OfflinePaymentsScreen extends ConsumerStatefulWidget {
  const OfflinePaymentsScreen({super.key});

  @override
  ConsumerState<OfflinePaymentsScreen> createState() => _OfflinePaymentsScreenState();
}

class _OfflinePaymentsScreenState extends ConsumerState<OfflinePaymentsScreen> {
  OfflineFeeStatus? _status = OfflineFeeStatus.toSettle;
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  OfflinePaymentsQuery get _query => (status: _status, schoolId: _schoolId, page: _page, perPage: _perPage);

  void _filter(VoidCallback change) => setState(() {
    change();
    _page = 1;
  });

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    final canSettle = actor != null && settlers.contains(actor.role) && actor.canManage(AppModules.fees);
    final mustPickSchool = actor?.picksSchool ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Offline Payments',
          actions: [
            SchoolFilterDropdown(selected: _schoolId, onChanged: (schoolId) => _filter(() => _schoolId = schoolId)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<OfflineFeeStatus?>(
              segments: [
                const ButtonSegment(value: OfflineFeeStatus.toSettle, label: Text('To settle')),
                const ButtonSegment(value: null, label: Text('All')),
              ],
              selected: {_status},
              onSelectionChanged: (selected) => _filter(() => _status = selected.first),
            ),
          ),
        ),
        Expanded(
          child: mustPickSchool && _schoolId == null
              ? const _Prompt('Choose a school to see its offline payments.')
              : AsyncValueView<PaginatedResponse<OfflineFeePayment>>(
                  value: ref.watch(offlinePaymentsProvider(_query)),
                  onRetry: () => ref.invalidate(offlinePaymentsProvider(_query)),
                  isEmpty: (page) => page.items.isEmpty,
                  emptyBuilder: (context) => _Prompt(
                    _status == OfflineFeeStatus.toSettle
                        ? 'Nothing to settle. Payments taken offline are receipted as soon as they arrive.'
                        : 'No fee has been taken offline yet.',
                  ),
                  data: (context, page) => Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          itemCount: page.items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _PaymentCard(
                            payment: page.items[index],
                            canSettle: canSettle,
                            onSettled: () => ref.invalidate(offlinePaymentsProvider),
                          ),
                        ),
                      ),
                      PaginationControls(
                        currentPage: page.currentPage,
                        lastPage: page.lastPage,
                        total: page.total,
                        perPage: page.perPage,
                        onPageChanged: (value) => setState(() => _page = value),
                        onPerPageChanged: (value) => _filter(() => _perPage = value),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.appColors.muted),
      ),
    ),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.canSettle, required this.onSettled});

  final OfflineFeePayment payment;
  final bool canSettle;
  final VoidCallback onSettled;

  BadgeTone get _tone => switch (payment.status) {
    OfflineFeeStatus.receipted || OfflineFeeStatus.credited => BadgeTone.success,
    OfflineFeeStatus.toSettle => BadgeTone.warning,
    OfflineFeeStatus.refunded => BadgeTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final outcome = switch (payment.status) {
      OfflineFeeStatus.receipted => 'Receipt ${payment.receiptNumber}',
      OfflineFeeStatus.credited => 'Kept on account - receipt ${payment.receiptNumber}',
      OfflineFeeStatus.refunded => 'Handed back${payment.settledBy == null ? '' : ' by ${payment.settledBy}'}',
      OfflineFeeStatus.toSettle => payment.problem ?? 'Waiting to be settled',
    };

    return Card(
      key: Key('offline-payment-${payment.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(payment.provisionalNumber, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(width: 8),
                      StatusBadge(label: payment.status.label, tone: _tone),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${payment.studentName} · ${payment.admissionNumber}'),
                  Text(
                    [
                      formatIsoDate(payment.receiptDate),
                      payment.paymentMode == 'cheque' ? 'Cheque ${payment.reference ?? ''}'.trim() : 'Cash',
                      if (payment.takenBy != null) 'taken by ${payment.takenBy}',
                    ].join(' · '),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(outcome, style: TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatCurrency(payment.amount, payment.currencyCode),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (canSettle && payment.status == OfflineFeeStatus.toSettle) ...[
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    key: Key('offline-payment-settle-${payment.id}'),
                    onPressed: () async {
                      final settled = await showDialog<bool>(
                        context: context,
                        builder: (_) => SettleOfflinePaymentDialog(payment: payment),
                      );
                      if (settled == true) onSettled();
                    },
                    child: const Text('Settle'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Choice { keep, handBack }

/// Keep the money on the student's account - a receipt now, paying what is
/// owed and holding the rest as credit - or record it handed back.
class SettleOfflinePaymentDialog extends ConsumerStatefulWidget {
  const SettleOfflinePaymentDialog({super.key, required this.payment});

  final OfflineFeePayment payment;

  @override
  ConsumerState<SettleOfflinePaymentDialog> createState() => _SettleOfflinePaymentDialogState();
}

class _SettleOfflinePaymentDialogState extends ConsumerState<SettleOfflinePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _reference = TextEditingController();

  _Choice _choice = _Choice.keep;
  String _mode = 'cash';
  bool _saving = false;
  String? _error;

  static const _modes = {'cash': 'Cash', 'cheque': 'Cheque', 'bank_transfer': 'Bank Transfer', 'upi': 'UPI'};

  @override
  void dispose() {
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(offlineFeesRepositoryProvider);
    final reason = _reason.text.trim();
    try {
      final settled = _choice == _Choice.keep
          ? await repository.keepOnAccount(widget.payment.id, reason: reason.isEmpty ? null : reason)
          : await repository.handBack(
              widget.payment.id,
              reason: reason,
              mode: _mode,
              reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            settled.status == OfflineFeeStatus.credited
                ? '${settled.provisionalNumber} kept on account as receipt ${settled.receiptNumber}.'
                : '${settled.provisionalNumber} recorded as handed back.',
          ),
        ),
      );
    } on Failure catch (failure) {
      debugPrint('Settling an offline payment failed: ${failure.code}');
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final handingBack = _choice == _Choice.handBack;

    return AlertDialog(
      title: Text('Settle ${payment.provisionalNumber}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogMessage(
                '${formatCurrency(payment.amount, payment.currencyCode)} from ${payment.studentName}, '
                        'taken ${formatIsoDate(payment.receiptDate)}. ${payment.problem ?? ''}'
                    .trim(),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_Choice>(
                segments: const [
                  ButtonSegment(value: _Choice.keep, label: Text('Keep on account')),
                  ButtonSegment(value: _Choice.handBack, label: Text('Handed back')),
                ],
                selected: {_choice},
                onSelectionChanged: _saving ? null : (selected) => setState(() => _choice = selected.first),
              ),
              const SizedBox(height: 8),
              Text(
                handingBack
                    ? 'Records that the money went back to the family. No receipt is made.'
                    : 'Makes the school\'s receipt now: it pays whatever is owed, oldest first, and holds the rest '
                          'as the student\'s credit.',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
              if (handingBack) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('settle-refund-mode'),
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Handed back by', isDense: true),
                        items: [
                          for (final entry in _modes.entries)
                            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                        ],
                        onChanged: _saving ? null : (mode) => setState(() => _mode = mode ?? 'cash'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('settle-reference'),
                        controller: _reference,
                        enabled: !_saving,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: _mode == 'cheque' ? 'Cheque number' : 'Reference (optional)',
                          isDense: true,
                          counterText: '',
                        ),
                        validator: (raw) =>
                            _mode == 'cheque' && (raw ?? '').trim().isEmpty ? 'Enter the cheque number' : null,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('settle-reason'),
                controller: _reason,
                enabled: !_saving,
                maxLength: 500,
                decoration: InputDecoration(labelText: handingBack ? 'Why' : 'Note (optional)', isDense: true),
                validator: (raw) {
                  final text = (raw ?? '').trim();
                  if (handingBack && text.isEmpty) return 'Say why it was handed back';
                  if (text.isNotEmpty && text.length < 3) return 'At least 3 characters';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('settle-error'),
                  style: TextStyle(color: context.appColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('settle-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(handingBack ? 'Record handed back' : 'Keep on account'),
        ),
      ],
    );
  }
}
