import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/payroll_notifiers.dart';
import '../data/models/payroll.dart';
import 'generate_run_dialog.dart';
import 'pay_dialog.dart';
import 'payslip_dialog.dart';
import 'salary_dialog.dart';

/// Payroll (Phase 19): a school's monthly runs and the salaries they are built
/// from - see docs/payroll.md.
///
/// An Accountant, a School Admin or a Group Admin runs it. A Super Admin reads
/// any school's payroll and changes none of it, so every action is hidden from
/// them here as well as refused by the server.
class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  static const managerRoles = {UserRole.accountant, UserRole.schoolAdmin, UserRole.groupAdmin};

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  int? _schoolFilter;

  /// The run being looked at, if any. Shown in place of the tabs rather than
  /// as a route of its own: it is one step into this screen, not a page
  /// somebody bookmarks.
  int? _openRunId;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authNotifierProvider).value?.role;
    final canManage = PayrollScreen.managerRoles.contains(role);

    if (_openRunId != null) {
      return _RunView(runId: _openRunId!, canManage: canManage, onBack: () => setState(() => _openRunId = null));
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Payroll',
            actions: [
              if (canManage)
                FilledButton.icon(
                  onPressed: () async {
                    final run = await showDialog<PayrollRun>(
                      context: context,
                      builder: (_) => const GenerateRunDialog(),
                    );
                    if (run != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(content: Text('Draft payroll generated for ${run.periodLabel}.')));
                      setState(() => _openRunId = run.id);
                    }
                  },
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Run Payroll'),
                ),
              SchoolFilterDropdown(
                selected: _schoolFilter,
                onChanged: (schoolId) {
                  setState(() => _schoolFilter = schoolId);
                  ref.read(payrollRunListNotifierProvider.notifier).setSchoolFilter(schoolId);
                  ref.read(salaryListNotifierProvider.notifier).setSchoolFilter(schoolId);
                },
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Runs'),
                Tab(text: 'Salaries'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RunsTab(onOpen: (run) => setState(() => _openRunId = run.id)),
                _SalariesTab(canManage: canManage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BadgeTone runTone(PayrollRunStatus status) => switch (status) {
  PayrollRunStatus.draft => BadgeTone.neutral,
  PayrollRunStatus.finalized => BadgeTone.warning,
  PayrollRunStatus.paid => BadgeTone.success,
};

String money(String amount, String currencyCode) => formatCurrency(double.parse(amount), currencyCode);

// -- runs -------------------------------------------------------------------

class _RunsTab extends ConsumerWidget {
  const _RunsTab({required this.onOpen});

  final ValueChanged<PayrollRun> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(payrollRunListNotifierProvider);
    final notifier = ref.read(payrollRunListNotifierProvider.notifier);

    return AsyncValueView<PagedList<PayrollRun>>(
      value: state,
      onRetry: notifier.refresh,
      isEmpty: (page) => page.items.isEmpty,
      emptyBuilder: (context) => const Center(child: Text('No payroll has been run yet.')),
      data: (context, page) => Column(
        children: [
          Expanded(
            child: ResponsiveBuilder(
              mobile: (context) => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: page.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final run = page.items[index];
                  return Card(
                    child: ListTile(
                      title: Text(run.periodLabel),
                      subtitle: Text(
                        '${run.schoolName}\n${run.employees} employees · net ${money(run.netTotal, run.currencyCode)}',
                      ),
                      isThreeLine: true,
                      trailing: StatusBadge(label: run.status.label, tone: runTone(run.status)),
                      onTap: () => onOpen(run),
                    ),
                  );
                },
              ),
              desktop: (context) => SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Month')),
                        DataColumn(label: Text('School')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Employees'), numeric: true),
                        DataColumn(label: Text('Net pay'), numeric: true),
                        DataColumn(label: Text('Paid'), numeric: true),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: [
                        for (final run in page.items)
                          DataRow(
                            cells: [
                              DataCell(Text(run.periodLabel)),
                              DataCell(Text(run.schoolName)),
                              DataCell(StatusBadge(label: run.status.label, tone: runTone(run.status))),
                              DataCell(Text('${run.employees}')),
                              DataCell(Text(money(run.netTotal, run.currencyCode))),
                              DataCell(Text('${run.paidCount}/${run.employees}')),
                              DataCell(TextButton(onPressed: () => onOpen(run), child: const Text('Open'))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
    );
  }
}

// -- salaries ---------------------------------------------------------------

class _SalariesTab extends ConsumerStatefulWidget {
  const _SalariesTab({required this.canManage});

  final bool canManage;

  @override
  ConsumerState<_SalariesTab> createState() => _SalariesTabState();
}

class _SalariesTabState extends ConsumerState<_SalariesTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(EmployeeSalary employee) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SalaryDialog(
        employee: employee,
        readOnly: !widget.canManage,
        onSave: (basic, components) =>
            ref.read(salaryListNotifierProvider.notifier).save(employee, basicSalary: basic, components: components),
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Salary saved for ${employee.name}.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salaryListNotifierProvider);
    final notifier = ref.read(salaryListNotifierProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DebouncedSearchField(
                  controller: _search,
                  onSearch: notifier.setSearch,
                  label: 'Search name / employee ID',
                ),
              ),
              FilterChip(
                label: const Text('No salary yet'),
                selected: notifier.missingOnly,
                onSelected: (selected) async {
                  await notifier.setMissingOnly(selected);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncValueView<PagedList<EmployeeSalary>>(
            value: state,
            onRetry: notifier.refresh,
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No employees match.')),
            data: (context, page) => Column(
              children: [
                Expanded(
                  child: ResponsiveBuilder(
                    mobile: (context) => ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: page.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final employee = page.items[index];
                        return Card(
                          child: ListTile(
                            title: Text(employee.name),
                            subtitle: Text('${employee.employeeId} · ${employee.role.label}\n${_salaryText(employee)}'),
                            isThreeLine: true,
                            trailing: _SalaryBadge(employee: employee),
                            onTap: () => _open(employee),
                          ),
                        );
                      },
                    ),
                    desktop: (context) => SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Card(
                        child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Employee')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Department')),
                              DataColumn(label: Text('Basic'), numeric: true),
                              DataColumn(label: Text('Net monthly'), numeric: true),
                              DataColumn(label: Text('Salary')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: [
                              for (final employee in page.items)
                                DataRow(
                                  cells: [
                                    DataCell(Text('${employee.name}\n${employee.employeeId}')),
                                    DataCell(Text(employee.role.label)),
                                    DataCell(Text(employee.departmentName ?? '-')),
                                    DataCell(
                                      Text(
                                        employee.salary == null
                                            ? '-'
                                            : money(employee.salary!.basicSalary, employee.salary!.currencyCode),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        employee.salary == null
                                            ? '-'
                                            : money(employee.salary!.netMonthly, employee.salary!.currencyCode),
                                      ),
                                    ),
                                    DataCell(_SalaryBadge(employee: employee)),
                                    DataCell(
                                      TextButton(
                                        onPressed: () => _open(employee),
                                        child: Text(
                                          widget.canManage
                                              ? (employee.salary == null ? 'Set Salary' : 'Edit Salary')
                                              : 'View',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

  String _salaryText(EmployeeSalary employee) {
    final salary = employee.salary;
    return salary == null ? 'No salary set' : 'Net monthly ${money(salary.netMonthly, salary.currencyCode)}';
  }
}

class _SalaryBadge extends StatelessWidget {
  const _SalaryBadge({required this.employee});

  final EmployeeSalary employee;

  @override
  Widget build(BuildContext context) {
    return employee.salary == null
        ? const StatusBadge(label: 'Not set', tone: BadgeTone.warning)
        : const StatusBadge(label: 'Set', tone: BadgeTone.success);
  }
}

// -- one run ----------------------------------------------------------------

class _RunView extends ConsumerStatefulWidget {
  const _RunView({required this.runId, required this.canManage, required this.onBack});

  final int runId;
  final bool canManage;
  final VoidCallback onBack;

  @override
  ConsumerState<_RunView> createState() => _RunViewState();
}

class _RunViewState extends ConsumerState<_RunView> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  PayrollRunNotifier get _notifier => ref.read(payrollRunNotifierProvider(widget.runId).notifier);

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform(Future<void> Function() action, String done) async {
    setState(() => _busy = true);

    try {
      await action();
      _show(done);
    } catch (error) {
      _show(error is Failure ? error.message : error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalize(PayrollRun run) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Finalize ${run.periodLabel}?',
      message:
          'Payslips are locked and emailed to each employee. After this, nothing on the run can be adjusted or '
          'regenerated - only payment can be recorded.',
      confirmLabel: 'Finalize',
    );

    if (confirmed) await _perform(_notifier.finalize, '${run.periodLabel} payroll finalized.');
  }

  Future<void> _delete(PayrollRun run) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Delete this draft?',
      message: 'The ${run.periodLabel} draft and its adjustments are removed. You can generate it again.',
      confirmLabel: 'Delete Draft',
      isDestructive: true,
    );

    if (!confirmed) return;

    await _perform(() async {
      await _notifier.delete();
      widget.onBack();
    }, 'Draft deleted.');
  }

  Future<void> _payAll(PayrollRun run) async {
    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => PayDialog(
        title: 'Mark ${run.unpaidCount} Payslips Paid',
        confirmLabel: 'Mark All Paid',
        onPay: (paidOn, mode, reference) => _notifier.payAll(paidOn: paidOn, mode: mode, reference: reference),
      ),
    );

    if (paid == true && mounted) _show('Payslips marked paid.');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(payrollRunNotifierProvider(widget.runId));

    return AsyncValueView<PayrollRunView>(
      value: state,
      onRetry: _notifier.refresh,
      data: (context, view) {
        final run = view.run;
        final page = view.payslips;

        final header = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(tooltip: 'Back to runs', icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
                Text('Payroll · ${run.periodLabel}', style: Theme.of(context).textTheme.titleLarge),
                StatusBadge(label: run.status.label, tone: runTone(run.status)),
                Text(run.schoolName, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                KpiCard(label: 'Employees', value: '${run.employees}'),
                KpiCard(label: 'Working days', value: '${run.workingDays}'),
                KpiCard(label: 'Gross', value: money(run.grossTotal, run.currencyCode)),
                KpiCard(label: 'Deductions', value: money(run.deductionsTotal, run.currencyCode)),
                KpiCard(label: 'Net pay', value: money(run.netTotal, run.currencyCode)),
                KpiCard(label: 'Paid', value: '${run.paidCount}/${run.employees}'),
              ],
            ),
          ),
          if (widget.canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (run.isDraft) ...[
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _perform(
                              _notifier.regenerate,
                              'Draft regenerated from current salaries and attendance.',
                            ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Regenerate'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || run.employees == 0 ? null : () => _finalize(run),
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('Finalize'),
                    ),
                    TextButton(onPressed: _busy ? null : () => _delete(run), child: const Text('Delete Draft')),
                  ],
                  if (run.status == PayrollRunStatus.finalized && run.unpaidCount > 0)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _payAll(run),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Mark All Paid'),
                    ),
                ],
              ),
            ),
          if (run.isDraft && run.missingSalaries.isNotEmpty) _MissingSalaries(missing: run.missingSalaries),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SizedBox(
              width: 280,
              child: DebouncedSearchField(controller: _search, onSearch: _notifier.setSearch, label: 'Search payslips'),
            ),
          ),
        ];
        final pagination = PaginationControls(
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
          perPage: page.perPage,
          onPageChanged: _notifier.goToPage,
          onPerPageChanged: _notifier.setPerPage,
        );
        final table = page.items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No payslips on this run.')),
              )
            : _PayslipTable(
                run: run,
                payslips: page.items,
                canManage: widget.canManage,
                onChanged: _notifier.payslipChanged,
              );

        // On a phone the figures, actions and warnings above the payslips
        // are taller than the screen, so the whole view scrolls as one list.
        // On a desktop they stay put and only the table scrolls.
        return ResponsiveBuilder(
          mobile: (context) => ListView(children: [...header, table, pagination]),
          desktop: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...header,
              Expanded(child: table),
              pagination,
            ],
          ),
        );
      },
    );
  }
}

class _MissingSalaries extends StatelessWidget {
  const _MissingSalaries({required this.missing});

  final List<MissingSalary> missing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${missing.length} employees are not on this run',
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
              ),
              const SizedBox(height: 4),
              for (final row in missing)
                Text(
                  '${row.name} (${row.employeeId}): ${row.reason}',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              const SizedBox(height: 4),
              Text(
                'Set their salary on the Salaries tab, then regenerate.',
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayslipTable extends StatelessWidget {
  const _PayslipTable({required this.run, required this.payslips, required this.canManage, required this.onChanged});

  final PayrollRun run;
  final List<Payslip> payslips;
  final bool canManage;
  final Future<void> Function() onChanged;

  void _open(BuildContext context, Payslip payslip) {
    showDialog<void>(
      context: context,
      builder: (_) => PayslipDialog(payslipId: payslip.id, canManage: canManage, onChanged: onChanged),
    );
  }

  StatusBadge _badge(Payslip payslip) => run.isDraft
      ? const StatusBadge(label: 'Draft', tone: BadgeTone.neutral)
      : StatusBadge(label: payslip.status.label, tone: payslip.isPaid ? BadgeTone.success : BadgeTone.warning);

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobile: (context) => ListView.separated(
        // Laid out in place inside the run view's own list, not scrolled
        // separately.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: payslips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final payslip = payslips[index];
          return Card(
            child: ListTile(
              title: Text(payslip.employeeName),
              subtitle: Text(
                '${payslip.employeeCode} · ${formatDays(payslip.paidDays)} paid days\n'
                'Net ${money(payslip.netPay, payslip.currencyCode)}',
              ),
              isThreeLine: true,
              trailing: _badge(payslip),
              onTap: () => _open(context, payslip),
            ),
          );
        },
      ),
      desktop: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Employee')),
                DataColumn(label: Text('Paid days'), numeric: true),
                DataColumn(label: Text('Gross'), numeric: true),
                DataColumn(label: Text('Deductions'), numeric: true),
                DataColumn(label: Text('Net pay'), numeric: true),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Action')),
              ],
              rows: [
                for (final payslip in payslips)
                  DataRow(
                    cells: [
                      DataCell(Text('${payslip.employeeName}\n${payslip.employeeCode}')),
                      DataCell(Text('${formatDays(payslip.paidDays)}/${formatDays(payslip.workingDays)}')),
                      DataCell(Text(money(payslip.grossEarnings, payslip.currencyCode))),
                      DataCell(Text(money(payslip.totalDeductions, payslip.currencyCode))),
                      DataCell(Text(money(payslip.netPay, payslip.currencyCode))),
                      DataCell(_badge(payslip)),
                      DataCell(TextButton(onPressed: () => _open(context, payslip), child: const Text('View'))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
