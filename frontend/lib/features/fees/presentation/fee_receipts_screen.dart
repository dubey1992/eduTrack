import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/student_fees_providers.dart';
import '../data/models/fee_receipt.dart';
import '../data/money_text.dart';
import 'widgets/receipt_actions.dart';

/// Every fee receipt the school has issued (docs/fees.md, F3): find one by
/// its number or the student, reprint it, email it, or cancel it.
class FeeReceiptsScreen extends ConsumerStatefulWidget {
  const FeeReceiptsScreen({super.key});

  @override
  ConsumerState<FeeReceiptsScreen> createState() => _FeeReceiptsScreenState();
}

class _FeeReceiptsScreenState extends ConsumerState<FeeReceiptsScreen> {
  final _search = TextEditingController();

  int? _schoolId;
  String _searchText = '';
  PaymentMode? _mode;

  /// null = all, true = cancelled only, false = valid only.
  bool? _cancelled;
  int _page = 1;
  int _perPage = 20;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(VoidCallback change) => setState(() {
    change();
    _page = 1;
  });

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    final mustPickSchool = actor?.picksSchool ?? false;
    final canManage = actor != null && actor.role != UserRole.superAdmin && actor.canManage(AppModules.fees);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Receipts',
          actions: [
            SchoolFilterDropdown(selected: _schoolId, onChanged: (schoolId) => _filter(() => _schoolId = schoolId)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: DebouncedSearchField(
                  controller: _search,
                  label: 'Receipt no., student or admission no.',
                  onSearch: (text) => _filter(() => _searchText = text),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<PaymentMode?>(
                  initialValue: _mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Paid by', isDense: true),
                  items: [
                    const DropdownMenuItem<PaymentMode?>(value: null, child: Text('Any')),
                    for (final mode in PaymentMode.values)
                      DropdownMenuItem<PaymentMode?>(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (mode) => _filter(() => _mode = mode),
                ),
              ),
              SegmentedButton<bool?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(value: false, label: Text('Valid')),
                  ButtonSegment(value: true, label: Text('Cancelled')),
                ],
                selected: {_cancelled},
                onSelectionChanged: (selected) => _filter(() => _cancelled = selected.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: mustPickSchool && _schoolId == null
              ? _Prompt(
                  message: actor?.role == UserRole.superAdmin
                      ? 'Choose a school to see its receipts.'
                      : 'Choose a branch to see its receipts.',
                )
              : _list(canManage),
        ),
      ],
    );
  }

  Widget _list(bool canManage) {
    final query = (
      schoolId: _schoolId,
      search: _searchText,
      mode: _mode,
      cancelled: _cancelled,
      page: _page,
      perPage: _perPage,
    );

    return AsyncValueView<PaginatedResponse<FeeReceipt>>(
      value: ref.watch(feeReceiptsProvider(query)),
      onRetry: () => ref.invalidate(feeReceiptsProvider(query)),
      isEmpty: (page) => page.items.isEmpty,
      emptyBuilder: (context) => _Prompt(
        message: _searchText.isNotEmpty || _mode != null || _cancelled != null
            ? 'No receipt matches these filters.'
            : 'No fee has been collected yet. Payments are recorded from a student\'s page under Student Fees.',
      ),
      data: (context, page) => Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _ReceiptCard(receipt: page.items[index], canManage: canManage),
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
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  const _ReceiptCard({required this.receipt, required this.canManage});

  final FeeReceipt receipt;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final strike = receipt.isCancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    final money = formatCurrency((centsOf(receipt.amount) ?? 0) / 100, receipt.currencyCode);
    final student = [receipt.studentName, receipt.admissionNumber, ?receipt.className].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(receipt.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w700).merge(strike)),
                      if (receipt.isCancelled) const StatusBadge(label: 'Cancelled', tone: BadgeTone.neutral),
                    ],
                  ),
                  Text(
                    '${formatDate(receipt.receiptDate)} · ${receipt.paymentMode.label}'
                    '${receipt.reference == null ? '' : ' ${receipt.reference}'}',
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                  InkWell(
                    onTap: () => context.go('/student-fees?student=${receipt.studentId}'),
                    child: Text(student, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                  ),
                  if (receipt.isCancelled && receipt.cancelReason != null)
                    Text('Cancelled: ${receipt.cancelReason}', style: TextStyle(color: colors.danger, fontSize: 13)),
                ],
              ),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(money, style: const TextStyle(fontWeight: FontWeight.w800).merge(strike)),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Download receipt',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => downloadReceipt(context, ref, id: receipt.id, number: receipt.receiptNumber),
                  ),
                  if (canManage && !receipt.isCancelled) ...[
                    IconButton(
                      tooltip: 'Email to guardian',
                      icon: const Icon(Icons.outgoing_mail),
                      onPressed: () => emailReceipt(context, ref, id: receipt.id),
                    ),
                    IconButton(
                      tooltip: 'Cancel receipt',
                      icon: Icon(Icons.block, color: colors.danger),
                      onPressed: () => cancelReceipt(context, ref, id: receipt.id, number: receipt.receiptNumber),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.appColors.muted),
        ),
      ),
    );
  }
}
