import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../data/fee_repository.dart';
import '../data/models/fee_receipt.dart';
import '../data/models/student_fees.dart';
import '../../today/presentation/staff_words.dart';

/// The year the phone's fee screens are about: the school's current one,
/// or its latest. The phone has no year picker - the website has.
final feesYearProvider = FutureProvider.autoDispose<AcademicYear?>((ref) async {
  final years = await ref.watch(academicYearPickerProvider(null).future);
  if (years.isEmpty) return null;
  return years.where((y) => y.isCurrent).firstOrNull ??
      (List.of(years)..sort((a, b) => b.startDate.compareTo(a.startDate))).first;
}, retry: (retryCount, error) => null);

/// Students of the year by name or admission number - "Collect".
final collectSearchProvider = FutureProvider.autoDispose.family<List<StudentBalance>, String>((ref, search) async {
  final year = await ref.watch(feesYearProvider.future);
  if (year == null) return const [];
  final page = await ref
      .read(feeRepositoryProvider)
      .balances(academicYearId: year.id, search: search, page: 1, perPage: 30);
  return page.items;
}, retry: (retryCount, error) => null);

/// Students with fees past their due date, most owed first as the server
/// lists them - "Overdue".
final overdueStudentsProvider = FutureProvider.autoDispose<List<StudentBalance>>((ref) async {
  final year = await ref.watch(feesYearProvider.future);
  if (year == null) return const [];
  final page = await ref
      .read(feeRepositoryProvider)
      .balances(academicYearId: year.id, overdueOnly: true, page: 1, perPage: 100);
  return page.items;
}, retry: (retryCount, error) => null);

/// Today's receipts that stand - "Today". The phone's date, which is the
/// school's for a phone at school.
final todaysReceiptsProvider = FutureProvider.autoDispose<List<FeeReceipt>>((ref) async {
  final today = apiDate(DateTime.now());
  final page = await ref.read(feeRepositoryProvider).receipts(from: today, to: today, cancelled: false, perPage: 200);
  return page.items;
}, retry: (retryCount, error) => null);

/// Opens the phone's dialler. Swappable in tests.
typedef FeesDialler = Future<bool> Function(Uri uri);

final feesDiallerProvider = Provider<FeesDialler>(
  (ref) =>
      (uri) => launchUrl(uri),
);

/// The Fees tab in the Staff app, for those who take payments - the
/// accountant and the School Admin (docs/mobile-apps-review.md, 7.2,
/// decided 2026-10-29): collect a payment, today's collection, and the
/// students overdue. A student opens their statement, where the payment is
/// recorded and the receipt shared - the website's own screen and rules.
class AccountantFeesScreen extends StatelessWidget {
  const AccountantFeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            key: const Key('fees-tabs'),
            tabs: [
              Tab(key: const Key('fees-tab-collect'), text: l10n.staffFeesCollect),
              Tab(key: const Key('fees-tab-today'), text: l10n.staffPeriodToday),
              Tab(key: const Key('fees-tab-overdue'), text: l10n.staffFeesOverdue),
            ],
          ),
          const Expanded(child: TabBarView(children: [_CollectTab(), _TodayTab(), _OverdueTab()])),
        ],
      ),
    );
  }
}

void _openStatement(BuildContext context, int studentId) => context.push('/fees/students/$studentId');

// -- Collect ------------------------------------------------------------------

class _CollectTab extends ConsumerStatefulWidget {
  const _CollectTab();

  @override
  ConsumerState<_CollectTab> createState() => _CollectTabState();
}

class _CollectTabState extends ConsumerState<_CollectTab> {
  String _search = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _typed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const Key('fees-collect-search'),
            onChanged: _typed,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.staffFeesFindStudent),
          ),
        ),
        Expanded(
          child: _search.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.staffFeesCollectHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted),
                  ),
                )
              : AsyncValueView<List<StudentBalance>>(
                  value: ref.watch(collectSearchProvider(_search)),
                  onRetry: () => ref.invalidate(collectSearchProvider(_search)),
                  isEmpty: (rows) => rows.isEmpty,
                  emptyBuilder: (context) => Center(
                    key: const Key('fees-collect-empty'),
                    child: Text(l10n.staffFeesNoMatch(_search), style: TextStyle(color: colors.muted)),
                  ),
                  data: (context, rows) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [for (final row in rows) _BalanceTile(row: row, figure: _Figure.balance)],
                  ),
                ),
        ),
      ],
    );
  }
}

// -- Today --------------------------------------------------------------------

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return RefreshIndicator(
      key: const Key('fees-today-refresh'),
      onRefresh: () => ref.refresh(todaysReceiptsProvider.future),
      child: AsyncValueView<List<FeeReceipt>>(
        value: ref.watch(todaysReceiptsProvider),
        onRetry: () => ref.invalidate(todaysReceiptsProvider),
        isEmpty: (receipts) => receipts.isEmpty,
        emptyBuilder: (context) => ListView(
          children: [
            Padding(
              key: const Key('fees-today-empty'),
              padding: const EdgeInsets.all(32),
              child: Text(
                context.l10n.staffFeesNothingToday,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ),
          ],
        ),
        data: (context, receipts) => ListView(
          key: const Key('fees-today-list'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _TodayTotals(receipts: receipts),
            const SizedBox(height: 12),
            for (final receipt in receipts)
              Card(
                key: Key('fees-today-receipt-${receipt.id}'),
                child: ListTile(
                  title: Text(receipt.studentName),
                  subtitle: Text(
                    [
                      receipt.receiptNumber,
                      paymentModeLabel(context.l10n, receipt.paymentMode.wire, receipt.paymentMode.label),
                      ?receipt.receivedByName,
                    ].join(' · '),
                  ),
                  trailing: Text(
                    _money(receipt.amount, receipt.currencyCode),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () => _openStatement(context, receipt.studentId),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Today in figures: the total in each currency, then each way it was paid.
/// Never one blended total across currencies (CLAUDE.md, section 5).
class _TodayTotals extends StatelessWidget {
  const _TodayTotals({required this.receipts});

  final List<FeeReceipt> receipts;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final byCurrency = <String, double>{};
    final byMode = <(String, PaymentMode), double>{};
    for (final receipt in receipts) {
      final amount = double.tryParse(receipt.amount) ?? 0;
      byCurrency.update(receipt.currencyCode, (sum) => sum + amount, ifAbsent: () => amount);
      byMode.update((receipt.currencyCode, receipt.paymentMode), (sum) => sum + amount, ifAbsent: () => amount);
    }

    return Card(
      key: const Key('fees-today-totals'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.staffReceiptsToday(receipts.length), style: TextStyle(color: colors.muted)),
            for (final entry in byCurrency.entries)
              Text(
                formatCurrency(entry.value, entry.key),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 8),
            for (final entry in byMode.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(paymentModeLabel(l10n, entry.key.$2.wire, entry.key.$2.label))),
                    Text(formatCurrency(entry.value, entry.key.$1)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -- Overdue ------------------------------------------------------------------

class _OverdueTab extends ConsumerWidget {
  const _OverdueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return RefreshIndicator(
      key: const Key('fees-overdue-refresh'),
      onRefresh: () => ref.refresh(overdueStudentsProvider.future),
      child: AsyncValueView<List<StudentBalance>>(
        value: ref.watch(overdueStudentsProvider),
        onRetry: () => ref.invalidate(overdueStudentsProvider),
        isEmpty: (rows) => rows.isEmpty,
        emptyBuilder: (context) => ListView(
          children: [
            Padding(
              key: const Key('fees-overdue-empty'),
              padding: const EdgeInsets.all(32),
              child: Text(
                context.l10n.staffFeesNobodyOverdue,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ),
          ],
        ),
        data: (context, rows) => ListView(
          key: const Key('fees-overdue-list'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(context.l10n.staffStudentsOverdue(rows.length), style: TextStyle(color: colors.muted)),
            const SizedBox(height: 8),
            for (final row in rows) _BalanceTile(row: row, figure: _Figure.overdue, canCall: true),
          ],
        ),
      ),
    );
  }
}

enum _Figure { balance, overdue }

class _BalanceTile extends ConsumerWidget {
  const _BalanceTile({required this.row, required this.figure, this.canCall = false});

  final StudentBalance row;
  final _Figure figure;
  final bool canCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final student = row.student;
    final mobile = student.guardianMobile;
    final amount = figure == _Figure.overdue ? row.overdue : row.balance;
    final l10n = context.l10n;

    return Card(
      key: Key('fees-student-${student.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openStatement(context, student.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      [if (student.classLabel.isNotEmpty) student.classLabel, student.admissionNumber].join(' · '),
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                    Text(
                      figure == _Figure.overdue
                          ? l10n.staffOverdueAmount(_money(amount, row.currencyCode))
                          : l10n.staffOwesAmount(_money(amount, row.currencyCode)),
                      style: TextStyle(
                        color: figure == _Figure.overdue ? colors.danger : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canCall && mobile != null && mobile.trim().isNotEmpty)
                IconButton(
                  key: Key('fees-call-${student.id}'),
                  tooltip: l10n.staffCallPerson(student.guardianName ?? l10n.staffTheGuardian),
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () async {
                    final opened = await ref.read(feesDiallerProvider)(
                      Uri(scheme: 'tel', path: mobile.replaceAll(' ', '')),
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.staffDiallerFailed)));
                    }
                  },
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String _money(String amount, String currencyCode) => formatCurrency(double.tryParse(amount) ?? 0, currencyCode);
