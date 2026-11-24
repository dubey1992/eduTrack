import 'widgets/saved_copy_line.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_learning_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_account.dart';
import '../data/models/family_fees.dart';
import 'family_more_screens.dart';
import 'family_words.dart';
import '../../../core/utils/pdf_hand_off.dart';
import 'widgets/family_widgets.dart';

/// Fees (docs/parent-student-app.md, F3): what is owed and overdue, how to
/// pay at this school, each instalment, every receipt and the year's
/// statement. Read only - the app takes no payments (decision D4).
class FamilyFeesScreen extends ConsumerWidget {
  const FamilyFeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);
    if (child == null) {
      return FamilyEmptyView(icon: Icons.family_restroom_rounded, title: context.l10n.familyNoChildrenTitle);
    }

    return ref
        .watch(familyFeesProvider(child.id))
        .when(
          skipLoadingOnRefresh: true,
          loading: () => const PlaceholderCards(count: 3),
          error: (error, _) =>
              FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyFeesProvider(child.id))),
          data: (fees) => RefreshIndicator(
            onRefresh: () => ref.read(familyFeesProvider(child.id).notifier).refresh(),
            child: _FeesList(child: child, fees: fees),
          ),
        );
  }
}

class _FeesList extends StatelessWidget {
  const _FeesList({required this.child, required this.fees});

  final FamilyChild child;
  final FamilyFees fees;

  @override
  Widget build(BuildContext context) {
    final totals = fees.totals;

    return ListView(
      key: const Key('family-fees'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SavedCopyLine(name: 'fees:${child.id}'),
        if (totals == null || fees.instalments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: FamilyEmptyView(
              icon: Icons.receipt_long_rounded,
              title: context.l10n.familyNoFeesYet,
              message: context.l10n.familyNoFeesYetMessage,
            ),
          )
        else
          _Summary(fees: fees, totals: totals),
        if (!fees.howToPay.isEmpty) ...[const SizedBox(height: 12), _HowToPay(fees: fees)],
        if (fees.instalments.isNotEmpty) ...[
          _SectionTitle(context.l10n.familyInstalments),
          for (final line in fees.instalments) ...[
            _InstalmentCard(line: line, currencyCode: fees.currencyCode),
            const SizedBox(height: 8),
          ],
        ],
        _SectionTitle(context.l10n.familyReceipts),
        if (fees.receipts.isEmpty)
          FamilyCard(
            child: Text(context.l10n.familyNoReceiptsYet, style: TextStyle(color: context.appColors.muted)),
          )
        else
          for (final receipt in fees.receipts) ...[
            _ReceiptCard(child: child, receipt: receipt),
            const SizedBox(height: 8),
          ],
        if (totals != null) ...[const SizedBox(height: 8), _StatementButton(child: child, yearName: fees.yearName)],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// What is left to pay this year, and how much of it is late.
class _Summary extends StatelessWidget {
  const _Summary({required this.fees, required this.totals});

  final FamilyFees fees;
  final FeeTotals totals;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final l10n = context.l10n;
    String money(double amount) => formatCurrency(amount, fees.currencyCode);
    final allPaid = totals.balance <= 0;

    return FamilyCard(
      key: const Key('family-fees-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            icon: allPaid ? Icons.verified_rounded : Icons.account_balance_wallet_rounded,
            title: fees.yearName == null ? l10n.familyThisYear : l10n.familyFeesFor(fees.yearName!),
            colour: allPaid ? colours.success : (totals.overdue > 0 ? colours.danger : colours.warning),
          ),
          const SizedBox(height: 14),
          Text(allPaid ? l10n.familyAllPaid : l10n.familyLeftToPay, style: TextStyle(color: colours.muted)),
          Text(
            money(totals.balance),
            key: const Key('family-fees-balance'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          if (totals.overdue > 0)
            Text(
              l10n.familyOfItOverdue(money(totals.overdue)),
              key: const Key('family-fees-overdue'),
              style: TextStyle(color: colours.danger, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Figure(label: l10n.familyCharged, value: money(totals.charged)),
              if (totals.discount > 0) _Figure(label: l10n.familyDiscount, value: money(totals.discount)),
              _Figure(label: l10n.familyFeeStatusPaid, value: money(totals.paid)),
              if (fees.waived > 0) _Figure(label: l10n.familyFeeStatusWaived, value: money(fees.waived)),
              if (fees.credit > 0) _Figure(label: l10n.familyCreditHeld, value: money(fees.credit)),
            ],
          ),
          const SizedBox(height: 4),
          HowWorkedOut(key: const Key('family-why-fees'), explanation: l10n.familyWhyFees),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.appColors.muted)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// How to pay at this school, as it wrote it: counter hours, UPI, bank.
class _HowToPay extends ConsumerWidget {
  const _HowToPay({required this.fees});

  final FamilyFees fees;

  HowToPay get pay => fees.howToPay;

  Future<void> _payByUpi(BuildContext context, WidgetRef ref, Uri link) async {
    final opened = await ref.read(externalOpenerProvider)(link);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(opened ? context.l10n.familyUpiOpened : context.l10n.familyUpiNotOpened)));
  }

  Future<void> _copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.familyCopied(what))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = context.appColors;
    final l10n = context.l10n;

    return FamilyCard(
      key: const Key('family-how-to-pay'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(icon: Icons.payments_rounded, title: l10n.familyHowToPay, colour: colours.info),
          const SizedBox(height: 4),
          Text(l10n.familyPaySchoolDirectly, style: TextStyle(fontSize: 13, color: colours.muted)),
          if (fees.upiPayLink case final link?) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('family-pay-upi'),
              onPressed: () => _payByUpi(context, ref, link),
              icon: const Icon(Icons.currency_rupee_rounded),
              label: Text(l10n.familyPayWithUpi(formatCurrency(fees.amountToPayNow!, fees.currencyCode))),
            ),
            const SizedBox(height: 4),
            Text(l10n.familyUpiExplain, style: TextStyle(fontSize: 12, color: colours.muted)),
          ],
          if (pay.counterHours != null)
            _PayRow(icon: Icons.schedule_rounded, label: l10n.familyFeeCounter, value: pay.counterHours!),
          if (pay.upiId != null)
            _PayRow(
              icon: Icons.qr_code_2_rounded,
              label: 'UPI',
              value: pay.upiId!,
              action: IconButton(
                key: const Key('family-copy-upi'),
                tooltip: l10n.familyCopyUpiId,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copy(context, pay.upiId!, l10n.familyUpiId),
              ),
            ),
          if (pay.bankDetails != null)
            _PayRow(
              icon: Icons.account_balance_rounded,
              label: l10n.familyPayModeBankTransfer,
              value: pay.bankDetails!,
              action: IconButton(
                key: const Key('family-copy-bank'),
                tooltip: l10n.familyCopyBankDetails,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copy(context, pay.bankDetails!, l10n.familyBankDetails),
              ),
            ),
          if (pay.officePhone != null)
            _PayRow(
              icon: Icons.call_rounded,
              label: l10n.familyFeeQuestions,
              value: pay.officePhone!,
              action: IconButton(
                key: const Key('family-call-office'),
                tooltip: l10n.familyCallSchoolOffice,
                icon: const Icon(Icons.call_rounded, size: 18),
                onPressed: () =>
                    ref.read(externalOpenerProvider)(Uri(scheme: 'tel', path: pay.officePhone!.replaceAll(' ', ''))),
              ),
            ),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.icon, required this.label, required this.value, this.action});

  final IconData icon;
  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: context.appColors.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: context.appColors.muted)),
                SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// One instalment: what, by when, how much, and where it stands.
class _InstalmentCard extends StatelessWidget {
  const _InstalmentCard({required this.line, required this.currencyCode});

  final Instalment line;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    String money(double amount) => formatCurrency(amount, currencyCode);
    final open =
        line.status == InstalmentStatus.due ||
        line.status == InstalmentStatus.partPaid ||
        line.status == InstalmentStatus.overdue;

    return FamilyCard(
      key: Key('family-instalment-${line.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  line.status == InstalmentStatus.overdue
                      ? context.l10n.familyWasDueDate(formatDate(line.dueDate))
                      : context.l10n.familyDueDate(formatDate(line.dueDate)),
                  style: TextStyle(
                    fontSize: 13,
                    color: line.status == InstalmentStatus.overdue ? colours.danger : colours.muted,
                  ),
                ),
                if (line.status == InstalmentStatus.partPaid ||
                    (line.status == InstalmentStatus.overdue && line.paid > 0))
                  Text(
                    context.l10n.familyPaidOf(money(line.paid), money(line.amount - line.discount)),
                    style: TextStyle(fontSize: 13, color: colours.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(open ? line.balance : line.amount - line.discount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              _StatusChip(status: line.status),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final InstalmentStatus status;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final (background, foreground) = switch (status) {
      InstalmentStatus.paid => (colours.successContainer, colours.onSuccessContainer),
      InstalmentStatus.overdue => (colours.dangerContainer, colours.onDangerContainer),
      InstalmentStatus.partPaid => (colours.warningContainer, colours.onWarningContainer),
      InstalmentStatus.due => (colours.infoContainer, colours.onInfoContainer),
      InstalmentStatus.waived => (
        Theme.of(context).colorScheme.surfaceContainerHighest,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
      child: Text(
        status.words(context.l10n),
        style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A PDF fetched for the parent, with the button busy while it comes.
mixin _PdfDownload<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool downloading = false;

  Future<void> download(Future<List<int>> Function(FamilyRepository repository) fetch, String fileName) async {
    if (downloading) return;
    setState(() => downloading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await fetch(ref.read(familyRepositoryProvider));
      await ref.read(pdfHandOffProvider)(bytes, fileName);
    } on Failure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }
}

class _ReceiptCard extends ConsumerStatefulWidget {
  const _ReceiptCard({required this.child, required this.receipt});

  final FamilyChild child;
  final FamilyReceipt receipt;

  @override
  ConsumerState<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends ConsumerState<_ReceiptCard> with _PdfDownload {
  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final colours = context.appColors;

    return FamilyCard(
      key: Key('family-receipt-${receipt.id}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      onTap: () => download(
        (repository) => repository.receiptPdf(widget.child.id, receipt.id),
        'receipt-${receipt.number.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.pdf',
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCurrency(receipt.amount, receipt.currencyCode),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: receipt.cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '${receipt.number} · ${formatDate(receipt.date)} · ${receipt.paymentModeWords(context.l10n)}',
                  style: TextStyle(fontSize: 13, color: colours.muted),
                ),
                if (receipt.cancelled)
                  Text(
                    context.l10n.familyCancelledByOffice,
                    style: TextStyle(fontSize: 13, color: colours.danger, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          downloading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: context.l10n.familyOpenReceipt,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  onPressed: () => download(
                    (repository) => repository.receiptPdf(widget.child.id, receipt.id),
                    'receipt-${receipt.number.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.pdf',
                  ),
                ),
        ],
      ),
    );
  }
}

class _StatementButton extends ConsumerStatefulWidget {
  const _StatementButton({required this.child, required this.yearName});

  final FamilyChild child;
  final String? yearName;

  @override
  ConsumerState<_StatementButton> createState() => _StatementButtonState();
}

class _StatementButtonState extends ConsumerState<_StatementButton> with _PdfDownload {
  @override
  Widget build(BuildContext context) {
    final year = (widget.yearName ?? 'this-year').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

    return OutlinedButton.icon(
      key: const Key('family-fee-statement'),
      onPressed: downloading
          ? null
          : () => download(
              (repository) => repository.feeStatement(widget.child.id),
              'fee-statement-${widget.child.firstName.toLowerCase()}-$year.pdf',
            ),
      icon: downloading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.description_rounded, size: 18),
      label: Text(
        widget.yearName == null ? context.l10n.familyYearStatement : context.l10n.familyStatementFor(widget.yearName!),
      ),
    );
  }
}
