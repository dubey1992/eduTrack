import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/report_notifier.dart';
import '../data/models/report.dart';
import '../data/report_repository.dart';
import '../../../core/utils/date_format.dart';

/// Phase 18 - the reports behind the dashboard's figures.
///
/// One screen for all four: they share a range, a table and an export, and
/// only their columns differ. Which reports a role may open is decided by the
/// API; this only avoids offering a tab that would answer 403.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportKind _kind = ReportKind.studentAttendance;
  int? _schoolId;
  DateTime? _from;
  DateTime? _to;
  bool _downloading = false;

  /// Which reports this role can actually open. Mirrors ReportController -
  /// offering a tab that answers 403 is a worse experience than not
  /// offering it.
  List<ReportKind> _kindsFor(UserRole? role) {
    return switch (role) {
      UserRole.superAdmin || UserRole.groupAdmin || UserRole.schoolAdmin => ReportKind.values,
      UserRole.hod => [ReportKind.staffAttendance, ReportKind.teachingCoverage],
      UserRole.transportManager => [ReportKind.transportUsage],
      _ => const [],
    };
  }

  String _iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  ReportQuery get _query => ReportQuery(
    kind: _kind,
    schoolId: _schoolId,
    from: _from == null ? null : _iso(_from!),
    to: _to == null ? null : _iso(_to!),
  );

  Future<void> _pickRange() async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 2),
      // A report covers days that have happened; the API refuses the rest.
      lastDate: today,
      initialDateRange: _from == null || _to == null ? null : DateTimeRange(start: _from!, end: _to!),
      helpText: 'Report period',
    );

    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final query = _query;
      final bytes = await ref
          .read(reportRepositoryProvider)
          .downloadCsv(
            query.kind,
            schoolId: query.schoolId,
            from: query.from,
            to: query.to,
            classSectionId: query.classSectionId,
            departmentId: query.departmentId,
          );

      saveBytes(
        fileName: '${query.kind.apiPath}-${query.from ?? 'start'}-to-${query.to ?? 'today'}.csv',
        bytes: bytes,
        mimeType: 'text/csv',
      );

      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Report downloaded.')));
    } catch (error) {
      final message = error is Failure ? error.message : error.toString().replaceFirst('UnsupportedError: ', '');
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authNotifierProvider).value?.role;
    final kinds = _kindsFor(role);

    if (kinds.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Reports are not available for your role.')),
      );
    }

    if (!kinds.contains(_kind)) _kind = kinds.first;

    final needsSchool = role == UserRole.superAdmin && _schoolId == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SchoolFilterDropdown(
                    selected: _schoolId,
                    onChanged: (schoolId) => setState(() => _schoolId = schoolId),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _from == null || _to == null ? 'This month' : '${formatDate(_from!)} - ${formatDate(_to!)}',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: needsSchool || _downloading ? null : _download,
                    icon: _downloading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_kind.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in kinds)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (needsSchool)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Pick a school to run a report.')),
              ),
            )
          else
            AsyncValueView<ReportResult>(
              value: ref.watch(reportProvider(_query)),
              onRetry: () => ref.invalidate(reportProvider(_query)),
              data: (context, report) => _ReportBody(kind: _kind, report: report),
            ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.kind, required this.report});

  final ReportKind kind;
  final ReportResult report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _Fact(label: 'Period', value: '${report.range.from} to ${report.range.to}'),
                // The denominator, stated: every rate below is out of this,
                // which is why a holiday cannot drag a percentage down. A
                // group has no single one - each branch keeps its own, shown
                // in the breakdown below.
                if (report.range.workingDays != null)
                  _Fact(label: 'Working days', value: '${report.range.workingDays}'),
                for (final entry in report.totals.entries)
                  if (entry.value != null && entry.key != 'working_days')
                    _Fact(label: _humanise(entry.key), value: _format(entry.value, entry.key.endsWith('rate'))),
              ],
            ),
          ),
        ),
        if (report.isGroup) ...[const SizedBox(height: 12), _BranchBreakdown(report: report)],
        const SizedBox(height: 12),
        if (report.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nothing to report for this period.')),
            ),
          )
        else if (report.range.workingDays == 0 && !report.isGroup)
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'The school did not run on any day in this period, so there is nothing to measure against.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          )
        else
          _ReportTable(kind: kind, report: report),
      ],
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.kind, required this.report});

  final ReportKind kind;
  final ReportResult report;

  @override
  Widget build(BuildContext context) {
    final columns = [
      // A group's rows come from several branches, so each line has to say
      // which - otherwise the table is a heap.
      if (report.isGroup) const ReportColumn('school_name', 'School'),
      ...reportColumns[kind] ?? const <ReportColumn>[],
    ];

    return Card(
      child: HorizontalScrollTable(
        child: DataTable(
          columnSpacing: 22,
          horizontalMargin: 12,
          columns: [for (final column in columns) DataColumn(label: Text(column.label), numeric: column.numeric)],
          rows: [
            for (final row in report.rows)
              DataRow(
                cells: [for (final column in columns) DataCell(_Cell(value: row[column.key], isRate: column.isRate))],
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.isRate});

  final Object? value;
  final bool isRate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (value == null) {
      // A missing rate means nobody counted, not that nobody came.
      return Text('-', style: TextStyle(color: scheme.onSurfaceVariant));
    }

    if (!isRate) return Text('$value');

    final rate = (value as num).toDouble();

    return Text(
      '${rate.toStringAsFixed(1)}%',
      style: TextStyle(fontWeight: FontWeight.w700, color: rate < 75 ? scheme.error : scheme.onSurface),
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
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

String _humanise(String key) {
  final words = key.split('_');

  return words.map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1)).join(' ');
}

String _format(Object? value, bool isRate) {
  if (value == null) return '-';

  return isRate ? '${(value as num).toStringAsFixed(1)}%' : '$value';
}

/// Each branch's own figures, above the combined table.
///
/// Every branch measures against its own working days, so the breakdown shows
/// them per branch rather than pretending the group has one number. The
/// combined totals above are recomputed from raw counts, never averaged - see
/// App\Support\Reports\GroupReport.
class _BranchBreakdown extends StatelessWidget {
  const _BranchBreakdown({required this.report});

  final ReportResult report;

  @override
  Widget build(BuildContext context) {
    final keys = report.branches
        .expand((branch) => branch.totals.keys)
        .where((key) => key != 'branches')
        .toSet()
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('By branch', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            HorizontalScrollTable(
              child: DataTable(
                columnSpacing: 22,
                horizontalMargin: 12,
                columns: [
                  const DataColumn(label: Text('School')),
                  const DataColumn(label: Text('Working days'), numeric: true),
                  for (final key in keys) DataColumn(label: Text(_humanise(key)), numeric: true),
                ],
                rows: [
                  for (final branch in report.branches)
                    DataRow(
                      cells: [
                        DataCell(Text(branch.schoolName)),
                        DataCell(Text('${branch.range.workingDays ?? '-'}')),
                        for (final key in keys)
                          DataCell(_Cell(value: branch.totals[key], isRate: key.endsWith('rate'))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
