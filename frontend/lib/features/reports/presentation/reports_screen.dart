import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/currency_formatter.dart';
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

/// Phase 18's reports behind the dashboard's figures, and Phase 20's on top.
///
/// One screen for all of them: they share a range, a table, a comparison and
/// an export, and only their columns differ. Which reports a role may open is decided by the
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
  bool _compare = false;
  int? _below;
  ExportFormat? _downloading;

  /// The chronic-absentee thresholds on offer, as a percentage.
  static const _belowOptions = [50, 75, 85, 90];

  /// Which reports this role can actually open. Mirrors ReportController -
  /// offering a tab that answers 403 is a worse experience than not
  /// offering it.
  List<ReportKind> _kindsFor(UserRole? role) {
    return switch (role) {
      UserRole.superAdmin || UserRole.groupAdmin || UserRole.schoolAdmin => ReportKind.values,
      UserRole.hod => [
        ReportKind.staffAttendance,
        ReportKind.teachingCoverage,
        ReportKind.leaveUsage,
        ReportKind.syllabusProgress,
      ],
      UserRole.transportManager => [ReportKind.transportUsage],
      UserRole.accountant => [ReportKind.staffAttendance, ReportKind.payrollSummary],
      _ => const [],
    };
  }

  String _iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  ReportQuery get _query => ReportQuery(
    kind: _kind,
    schoolId: _schoolId,
    from: _from == null ? null : _iso(_from!),
    to: _to == null ? null : _iso(_to!),
    compare: _compare,
    // Only the student report narrows to chronic absentees.
    below: _kind == ReportKind.studentAttendance ? _below : null,
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

  Future<void> _download(ExportFormat format) async {
    setState(() => _downloading = format);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final query = _query;
      final bytes = await ref
          .read(reportRepositoryProvider)
          .download(
            query.kind,
            format,
            schoolId: query.schoolId,
            from: query.from,
            to: query.to,
            classSectionId: query.classSectionId,
            departmentId: query.departmentId,
            compare: query.compare,
            below: query.below,
          );

      saveBytes(
        fileName: '${query.kind.apiPath}-${query.from ?? 'start'}-to-${query.to ?? 'today'}.${format.apiValue}',
        bytes: bytes,
        mimeType: format.mimeType,
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
      if (mounted) setState(() => _downloading = null);
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
                  for (final format in ExportFormat.values)
                    FilledButton.tonalIcon(
                      onPressed: needsSchool || _downloading != null ? null : () => _download(format),
                      icon: _downloading == format
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              format == ExportFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.download_outlined,
                              size: 18,
                            ),
                      label: Text('Export ${format.label}'),
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Compare with previous period'),
                selected: _compare,
                onSelected: (selected) => setState(() => _compare = selected),
              ),
              if (_kind == ReportKind.studentAttendance)
                DropdownButton<int?>(
                  value: _below,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All students')),
                    for (final threshold in _belowOptions)
                      DropdownMenuItem<int?>(value: threshold, child: Text('Below $threshold% attendance')),
                  ],
                  onChanged: (value) => setState(() => _below = value),
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
    final comparison = report.comparison;

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
                  if (entry.value != null && entry.key != 'working_days' && entry.key != 'by_currency')
                    _Fact(
                      label: _humanise(entry.key),
                      value: _format(entry.value, _isRateKey(entry.key)),
                      previous: comparison == null
                          ? null
                          : _format(comparison.totals[entry.key], _isRateKey(entry.key)),
                    ),
                // Payroll's money, one figure per currency - never added
                // across them.
                for (final entry in _currencyTotals(report.totals))
                  _Fact(
                    label: 'Net pay (${entry['currency_code']})',
                    value: _money(entry['net'], entry['currency_code'] as String),
                    previous: comparison == null ? null : _previousNet(comparison.totals, entry['currency_code']),
                  ),
                if (comparison != null)
                  _Fact(label: 'Previous period', value: '${comparison.range.from} to ${comparison.range.to}'),
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
                cells: [
                  for (final column in columns)
                    DataCell(
                      _Cell(
                        value: row[column.key],
                        isRate: column.isRate,
                        currencyCode: column.isMoney ? row['currency_code'] as String? : null,
                        comparison: _earlier(row, column.key),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A row's earlier figure for [key], when the report was compared and this
/// column is one of those compared. Wrapped so "compared, but the row did
/// not exist then" (a null inside) differs from "not compared" (no wrapper).
({Object? value})? _earlier(Map<String, dynamic> row, String key) {
  final previous = row['previous'];
  if (previous is! Map<String, dynamic> || !previous.containsKey(key)) return null;

  return (value: previous[key]);
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.isRate, this.currencyCode, this.comparison});

  final Object? value;
  final bool isRate;

  /// Set for money: the amount is shown in this currency.
  final String? currencyCode;

  final ({Object? value})? comparison;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (value == null) {
      // A missing rate means nobody counted, not that nobody came.
      return Text('-', style: TextStyle(color: scheme.onSurfaceVariant));
    }

    final Widget main;
    if (currencyCode != null) {
      main = Text(_money(value, currencyCode!));
    } else if (isRate) {
      final rate = (value as num).toDouble();
      main = Text(
        '${rate.toStringAsFixed(1)}%',
        style: TextStyle(fontWeight: FontWeight.w700, color: rate < 75 ? scheme.error : scheme.onSurface),
      );
    } else {
      main = Text('$value');
    }

    final comparison = this.comparison;
    if (comparison == null) return main;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        main,
        const SizedBox(width: 6),
        _Change(now: value, before: comparison.value, isRate: isRate),
      ],
    );
  }
}

/// How a figure moved since the previous period: "+4.0", "-2", or "new" for
/// a row that did not exist then. Neutral in colour - more leave or more
/// trips is not good or bad in itself.
class _Change extends StatelessWidget {
  const _Change({required this.now, required this.before, required this.isRate});

  final Object? now;
  final Object? before;
  final bool isRate;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final current = _number(now);
    final earlier = _number(before);

    if (earlier == null) return Text('(new)', style: style);
    if (current == null) return const SizedBox.shrink();

    return Text('(${_signed(current - earlier, isRate)})', style: style);
  }
}

double? _number(Object? value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};

String _signed(double change, bool isRate) {
  final String text;
  if (isRate) {
    text = change.toStringAsFixed(1);
  } else if (change == change.roundToDouble()) {
    text = '${change.round()}';
  } else {
    text = change.toStringAsFixed(2);
  }

  return change > 0 ? '+$text' : text;
}

String _money(Object? amount, String currencyCode) {
  final value = _number(amount);

  return value == null ? '-' : formatCurrency(value, currencyCode);
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.previous});

  final String label;
  final String value;

  /// The same figure for the previous period, when one was asked for.
  final String? previous;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: muted)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (previous != null) Text('was $previous', style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }
}

String _humanise(String key) {
  final words = key.split('_');

  return words.map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1)).join(' ');
}

bool _isRateKey(String key) => key.endsWith('rate') || key.endsWith('completion');

String _format(Object? value, bool isRate) {
  if (value == null) return '-';
  if (value is List) return value.isEmpty ? '-' : value.join(', ');

  return isRate ? '${(value as num).toStringAsFixed(1)}%' : '$value';
}

List<Map<String, dynamic>> _currencyTotals(Map<String, dynamic> totals) {
  return (totals['by_currency'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
}

String _previousNet(Map<String, dynamic> previousTotals, Object? currencyCode) {
  for (final entry in _currencyTotals(previousTotals)) {
    if (entry['currency_code'] == currencyCode) return _money(entry['net'], currencyCode as String);
  }

  return '-';
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
