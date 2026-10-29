import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../application/analytics_notifier.dart';
import '../../data/models/finance_overview.dart';
import 'trend_bar_chart.dart';

/// "Finance" on the Analytics page (docs/analytics.md, A5): a school's fee
/// money month by month, overdue by age, by class, what is scheduled next,
/// and - for whoever may read payroll - fees against payroll.
///
/// One block per currency: money is never added across currencies, so a
/// school that bills in two gets two sets of figures, never one blend.
class FinanceView extends ConsumerWidget {
  const FinanceView({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (schoolId: schoolId, from: null, to: null);

    return AsyncValueView<FinanceOverview>(
      value: ref.watch(financeOverviewProvider(query)),
      onRetry: () => ref.invalidate(financeOverviewProvider(query)),
      data: (context, overview) {
        if (overview.isEmpty) {
          return const _Notice('No fees have been charged or collected in the last twelve months.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final code in overview.currencies) ...[
              if (overview.currencies.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('In $code', style: Theme.of(context).textTheme.titleLarge),
                ),
              _CollectionCard(overview: overview, code: code),
              const SizedBox(height: 16),
              _UpcomingCard(overview: overview, code: code),
              const SizedBox(height: 16),
              _AgesCard(overview: overview, code: code),
              const SizedBox(height: 16),
              _ByClassCard(overview: overview, code: code),
              if (overview.feesVsPayroll != null) ...[
                const SizedBox(height: 16),
                _PayrollCard(overview: overview, code: code),
              ],
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }
}

String _month(String iso) => DateFormat('MMM yyyy').format(DateTime.parse(iso));

String _money(double value, String code) => formatCurrency(value, code);

String _rate(double? rate) =>
    rate == null ? '-' : '${rate == rate.roundToDouble() ? rate.round() : rate.toStringAsFixed(1)}%';

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.overview, required this.code});

  final FinanceOverview overview;
  final String code;

  @override
  Widget build(BuildContext context) {
    final months = overview.collection;
    final collected = [for (final month in months) month.currency(code)?['collected'] ?? 0.0];
    final top = collected.fold<double>(0, (a, b) => a > b ? a : b);

    return _Section(
      title: 'Collected by month',
      note:
          '"Paid so far" is how much of what fell due that month has been paid by today, so an old month '
          'keeps rising as families pay late.',
      children: [
        TrendBarChart(
          maxValue: top,
          bars: [
            for (var i = 0; i < months.length; i++)
              TrendBar(label: _month(months[i].from), value: collected[i], valueLabel: _money(collected[i], code)),
          ],
        ),
        const SizedBox(height: 12),
        _Table(
          columns: const ['Month', 'Fell due', 'Collected', 'Paid so far', 'Of what fell due'],
          rows: [
            for (final month in months.reversed)
              [
                _month(month.from),
                _money(month.currency(code)?['due'] ?? 0, code),
                _money(month.currency(code)?['collected'] ?? 0, code),
                _money(month.currency(code)?['paid_so_far'] ?? 0, code),
                _rate(month.currency(code)?.rate),
              ],
          ],
        ),
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.overview, required this.code});

  final FinanceOverview overview;
  final String code;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Falling due next',
      note: 'What the fee plans schedule for the next three months and is not yet paid - not a forecast.',
      children: [
        Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            for (final month in overview.upcoming)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _month(month.from),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _money(month.currency(code)?['due'] ?? 0, code),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _AgesCard extends StatelessWidget {
  const _AgesCard({required this.overview, required this.code});

  final FinanceOverview overview;
  final String code;

  @override
  Widget build(BuildContext context) {
    final recorded = overview.overdueByAge.where((month) => month.amounts != null).toList();

    return _Section(
      title: 'Overdue by age',
      note:
          'At the last recorded night of each month. Recorded nightly from when this was switched on, so '
          'earlier months have no figure.',
      children: [
        if (recorded.isEmpty)
          const Text('Nothing recorded yet - the first figures appear after tonight.')
        else
          _Table(
            columns: const ['Month', '1-30 days', '31-60 days', '61+ days'],
            rows: [
              for (final month in recorded.reversed)
                [
                  '${_month(month.from)} (${formatIsoDate(month.asOf)})',
                  _money(month.currency(code)?['overdue_0_30'] ?? 0, code),
                  _money(month.currency(code)?['overdue_31_60'] ?? 0, code),
                  _money(month.currency(code)?['overdue_61_plus'] ?? 0, code),
                ],
            ],
          ),
      ],
    );
  }
}

class _ByClassCard extends StatelessWidget {
  const _ByClassCard({required this.overview, required this.code});

  final FinanceOverview overview;
  final String code;

  @override
  Widget build(BuildContext context) {
    final rows = overview.byClass.where((row) => row.amounts.currencyCode == code).toList();

    return _Section(
      title: 'By class, today',
      note:
          'Everything that has fallen due so far this year, by the class each student is in now. '
          'Most owed first.',
      children: [
        if (rows.isEmpty)
          const Text('Nothing has fallen due yet.')
        else
          _Table(
            columns: const ['Class', 'Charged', 'Paid', 'Owed', 'Overdue', 'Collected'],
            rows: [
              for (final row in rows)
                [
                  row.classSection,
                  _money(row.amounts['charged'], code),
                  _money(row.amounts['paid'], code),
                  _money(row.amounts['outstanding'], code),
                  _money(row.amounts['overdue'], code),
                  _rate(row.amounts.rate),
                ],
            ],
          ),
      ],
    );
  }
}

class _PayrollCard extends StatelessWidget {
  const _PayrollCard({required this.overview, required this.code});

  final FinanceOverview overview;
  final String code;

  @override
  Widget build(BuildContext context) {
    final months = overview.feesVsPayroll!;

    return _Section(
      title: 'Fees and payroll',
      note: 'Fees collected in each month against the payroll finalized for it (net pay).',
      children: [
        _Table(
          columns: const ['Month', 'Fees in', 'Payroll out', 'Difference'],
          rows: [
            for (final month in months.reversed)
              () {
                final line = month.currency(code);
                final fees = line?['fees_in'] ?? 0;
                final payroll = line?['payroll_out'] ?? 0;

                return [_month(month.from), _money(fees, code), _money(payroll, code), _money(fees - payroll, code)];
              }(),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.note, required this.children});

  final String title;
  final String note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(note, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollTable(
      child: DataTable(
        columns: [for (var i = 0; i < columns.length; i++) DataColumn(label: Text(columns[i]), numeric: i > 0)],
        rows: [
          for (final row in rows) DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}
