import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/network/paginated_response.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../../../core/widgets/pagination_controls.dart';
import '../../../schools/data/models/school.dart' show SchoolCategory;
import '../../application/analytics_notifier.dart';
import '../../data/analytics_repository.dart' show PlatformSchoolsQuery;
import '../../data/models/platform_overview.dart';

/// "Platform" on the Analytics page (docs/analytics.md, A7): the whole of
/// School365ai for the Super Admin - what it carries now, each month's
/// growth and use, each school's recent activity, and module adoption.
class PlatformView extends ConsumerWidget {
  const PlatformView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<PlatformOverview>(
      value: ref.watch(platformOverviewProvider),
      onRetry: () => ref.invalidate(platformOverviewProvider),
      data: (context, overview) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TotalsCard(totals: overview.totals),
          const SizedBox(height: 16),
          _MonthsCard(months: overview.months),
          const SizedBox(height: 16),
          _SchoolsCard(recentDays: overview.recentDays),
          const SizedBox(height: 16),
          _ModulesCard(modules: overview.modules),
        ],
      ),
    );
  }
}

String _month(String iso) => DateFormat('MMM yyyy').format(DateTime.parse(iso));

/// "12 sent, 1 failed", or a dash for a channel that sent nothing.
String _channel(({int sent, int failed})? counts) {
  if (counts == null || (counts.sent == 0 && counts.failed == 0)) return '-';

  return counts.failed == 0 ? '${counts.sent}' : '${counts.sent} (${counts.failed} failed)';
}

/// Each currency on its own line; never one blended total.
String _payments(List<PlatformPayment> payments) {
  if (payments.isEmpty) return '-';

  return payments.map((p) => formatCurrency(double.parse(p.amount), p.currencyCode)).join('\n');
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final PlatformTotals totals;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Now',
      note:
          'Live and in-trial schools only: students and staff on roll, and accounts that can sign in. '
          'Demo and testing schools are left out of every figure on this page.',
      child: Wrap(
        spacing: 32,
        runSpacing: 12,
        children: [
          _Fact(label: 'Active schools', value: '${totals.schoolsActive}'),
          _Fact(label: 'Inactive schools', value: '${totals.schoolsInactive}'),
          _Fact(label: 'Demo & testing (not counted)', value: '${totals.schoolsNotCounted}'),
          _Fact(label: 'Students', value: '${totals.students}'),
          _Fact(label: 'Staff', value: '${totals.staff}'),
          _Fact(label: 'Accounts', value: '${totals.users}'),
        ],
      ),
    );
  }
}

class _MonthsCard extends StatelessWidget {
  const _MonthsCard({required this.months});

  final List<PlatformMonth> months;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Month by month',
      note:
          'People signing in counts each person once a month. Messages are those sent or failed; '
          'payments are those received from schools, each currency on its own.',
      child: _Table(
        columns: const [
          'Month',
          'New schools',
          'Sign-ins',
          'People signing in',
          'SMS',
          'WhatsApp',
          'Email',
          'Payments received',
          'Early access',
          'Demo requests',
        ],
        rows: [
          for (final month in months.reversed)
            [
              _month(month.from),
              '${month.newSchools}',
              '${month.signIns}',
              '${month.activeUsers}',
              _channel(month.messages['sms']),
              _channel(month.messages['whatsapp']),
              _channel(month.messages['email']),
              _payments(month.payments),
              '${month.earlyAccessRequests}',
              '${month.demoRequests}',
            ],
        ],
      ),
    );
  }
}

/// Each school a page at a time, searchable and by category - a platform
/// past a few hundred schools is a list somebody searches, not one they
/// scroll (A7).
class _SchoolsCard extends ConsumerStatefulWidget {
  const _SchoolsCard({required this.recentDays});

  final int recentDays;

  @override
  ConsumerState<_SchoolsCard> createState() => _SchoolsCardState();
}

class _SchoolsCardState extends ConsumerState<_SchoolsCard> {
  PlatformSchoolsQuery _query = const PlatformSchoolsQuery();
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  /// Debounced, and back to page one: the answer wanted is the one for what
  /// somebody finished typing.
  void _search(String term) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = _query.copyWith(q: term.trim(), page: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.recentDays;

    return _Section(
      title: 'Each school',
      note:
          'Busiest first over the last $days days; a school near the bottom of the active ones has gone quiet. '
          'Demo and testing schools come after the customers, and inactive schools last.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  key: const Key('platform-schools-search'),
                  decoration: const InputDecoration(
                    labelText: 'Search by name or city',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: _search,
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  key: const Key('platform-schools-category'),
                  initialValue: _query.category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final category in SchoolCategory.values)
                      DropdownMenuItem(value: category.apiValue, child: Text(category.label)),
                  ],
                  onChanged: (chosen) =>
                      setState(() => _query = _query.copyWith(category: chosen, changeCategory: true, page: 1)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AsyncValueView<PaginatedResponse<PlatformSchool>>(
            value: ref.watch(platformSchoolsProvider(_query)),
            onRetry: () => ref.invalidate(platformSchoolsProvider(_query)),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => Text(
              _query.q.isEmpty && _query.category == null
                  ? 'There are no schools yet.'
                  : 'No school matches this search.',
            ),
            data: (context, page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Table(
                  columns: [
                    'School',
                    'Category',
                    'Status',
                    'Students',
                    'Staff',
                    'Last sign-in',
                    'Sign-ins ($days days)',
                    'Messages sent ($days days)',
                  ],
                  numericFrom: 3,
                  rows: [
                    for (final school in page.items)
                      [
                        school.city == null || school.city!.isEmpty ? school.name : '${school.name}, ${school.city}',
                        school.categoryText,
                        school.isActive ? 'Active' : 'Inactive',
                        '${school.students}',
                        '${school.staff}',
                        school.lastSignInLabel ?? 'Never',
                        '${school.recentSignIns}',
                        '${school.recentMessages}',
                      ],
                  ],
                ),
                PaginationControls(
                  currentPage: page.currentPage,
                  lastPage: page.lastPage,
                  total: page.total,
                  perPage: page.perPage,
                  onPageChanged: (number) => setState(() => _query = _query.copyWith(page: number)),
                  onPerPageChanged: (size) => setState(() => _query = _query.copyWith(perPage: size, page: 1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModulesCard extends StatelessWidget {
  const _ModulesCard({required this.modules});

  final List<PlatformModule> modules;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Modules in use',
      note: 'How many active schools have each module switched on.',
      child: _Table(
        columns: const ['Module', 'Schools using it'],
        rows: [
          for (final module in modules) [module.label, '${module.schoolsOn} of ${module.schools}'],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.note, required this.child});

  final String title;
  final String note;
  final Widget child;

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
            child,
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows, this.numericFrom = 1});

  final List<String> columns;
  final List<List<String>> rows;

  /// The first column holding a number; those from it on are right-aligned.
  final int numericFrom;

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollTable(
      child: DataTable(
        dataRowMaxHeight: double.infinity,
        columns: [
          for (var i = 0; i < columns.length; i++) DataColumn(label: Text(columns[i]), numeric: i >= numericFrom),
        ],
        rows: [
          for (final row in rows) DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
