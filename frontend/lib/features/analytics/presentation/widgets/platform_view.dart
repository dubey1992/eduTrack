import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../application/analytics_notifier.dart';
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
          _SchoolsCard(schools: overview.schools, recentDays: overview.recentDays),
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
      note: 'Students and staff on roll, and accounts that can sign in, across every school.',
      child: Wrap(
        spacing: 32,
        runSpacing: 12,
        children: [
          _Fact(label: 'Active schools', value: '${totals.schoolsActive}'),
          _Fact(label: 'Inactive schools', value: '${totals.schoolsInactive}'),
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

class _SchoolsCard extends StatelessWidget {
  const _SchoolsCard({required this.schools, required this.recentDays});

  final List<PlatformSchool> schools;
  final int recentDays;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Each school',
      note:
          'Busiest first over the last $recentDays days; a school near the bottom of the active ones has gone '
          'quiet. Inactive schools come last.',
      child: schools.isEmpty
          ? const Text('There are no schools yet.')
          : _Table(
              columns: [
                'School',
                'Status',
                'Students',
                'Staff',
                'Last sign-in',
                'Sign-ins ($recentDays days)',
                'Messages sent ($recentDays days)',
              ],
              rows: [
                for (final school in schools)
                  [
                    school.city == null || school.city!.isEmpty ? school.name : '${school.name}, ${school.city}',
                    school.isActive ? 'Active' : 'Inactive',
                    '${school.students}',
                    '${school.staff}',
                    school.lastSignInLabel ?? 'Never',
                    '${school.recentSignIns}',
                    '${school.recentMessages}',
                  ],
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
  const _Table({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollTable(
      child: DataTable(
        dataRowMaxHeight: double.infinity,
        columns: [for (var i = 0; i < columns.length; i++) DataColumn(label: Text(columns[i]), numeric: i > 0)],
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
