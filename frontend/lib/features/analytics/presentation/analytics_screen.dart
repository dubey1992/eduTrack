import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/user_role.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/analytics_notifier.dart';
import '../data/models/analytics_series.dart';
import 'series_line.dart';
import 'widgets/academic_view.dart';
import 'widgets/trend_bar_chart.dart';

/// School Analytics (docs/analytics.md, A2): one figure over time, week by
/// week or month by month.
///
/// Every point is the matching report's own figure for that period, so this
/// screen only draws what the server sends. What it has to get right is
/// showing a gap as a gap, and never adding money across currencies.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key, this.initialMeasure, this.initialSchoolId});

  /// Where a dashboard trend card opens it: on that card's measure and
  /// school. A measure the person may not chart falls back to the first one.
  final String? initialMeasure;
  final int? initialSchoolId;

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late String? _measure = widget.initialMeasure;
  AnalyticsInterval _interval = AnalyticsInterval.month;
  late int? _schoolId = widget.initialSchoolId;
  DateTime? _from;
  DateTime? _to;

  /// Trends over time (A1-A2), or subjects and classes term by term (A4).
  bool _academic = false;

  /// Who reads the class performance report the term view is built from.
  static const _academicRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod};

  String _iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _pickRange() async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 2, today.month),
      // A chart covers days that have happened; the API refuses the rest.
      lastDate: today,
      initialDateRange: _from == null || _to == null ? null : DateTimeRange(start: _from!, end: _to!),
      helpText: 'Chart period',
    );

    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  String get _rangeLabel {
    if (_from == null || _to == null) {
      return _interval == AnalyticsInterval.week ? 'Last 12 weeks' : 'Last 12 months';
    }

    return '${formatDate(_from!)} - ${formatDate(_to!)}';
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    // Someone who spans schools charts one at a time (A1): the whole group
    // is not a figure the server gives yet.
    final needsSchool = actor != null && actor.picksSchool && _schoolId == null;
    final offersAcademic = actor != null && _academicRoles.contains(actor.role);
    final academic = _academic && offersAcademic;

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
              Text('Analytics', style: Theme.of(context).textTheme.headlineSmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SchoolFilterDropdown(
                    selected: _schoolId,
                    onChanged: (schoolId) => setState(() => _schoolId = schoolId),
                  ),
                  if (offersAcademic)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Trends')),
                        ButtonSegment(value: true, label: Text('Subjects & classes')),
                      ],
                      selected: {academic},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) => setState(() => _academic = selection.single),
                    ),
                  if (!academic) ...[
                    SegmentedButton<AnalyticsInterval>(
                      segments: const [
                        ButtonSegment(value: AnalyticsInterval.week, label: Text('By week')),
                        ButtonSegment(value: AnalyticsInterval.month, label: Text('By month')),
                      ],
                      selected: {_interval},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) => setState(() => _interval = selection.single),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(_rangeLabel),
                    ),
                    if (_from != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _from = null;
                          _to = null;
                        }),
                        child: const Text('Reset range'),
                      ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            academic
                ? 'How each subject and class did, term by term - the Class Performance report for each term.'
                : "How the school's figures move over time. Each bar is that period's figure from the matching report.",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (academic)
            needsSchool
                ? _Notice(
                    actor.role == UserRole.superAdmin
                        ? 'Pick a school to see its subjects and classes.'
                        : 'Pick a branch to see its subjects and classes.',
                  )
                : AcademicView(schoolId: _schoolId)
          else
            AsyncValueView<List<AnalyticsMeasure>>(
              value: ref.watch(analyticsMeasuresProvider),
              onRetry: () => ref.invalidate(analyticsMeasuresProvider),
              isEmpty: (measures) => measures.isEmpty,
              emptyBuilder: (context) => const _Notice('There are no charts for your role yet.'),
              data: (context, measures) {
                final measure = measures.firstWhere((m) => m.key == _measure, orElse: () => measures.first);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in measures)
                          ChoiceChip(
                            label: Text(option.label),
                            selected: option.key == measure.key,
                            onSelected: (_) => setState(() => _measure = option.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (needsSchool)
                      _Notice(
                        actor.role == UserRole.superAdmin
                            ? 'Pick a school to see its charts.'
                            // The dropdown offers the whole group, which is
                            // not a figure the server gives yet.
                            : 'Pick a branch to see its charts. Charts for the whole group together are not '
                                  'available yet.',
                      )
                    else
                      _SeriesView(
                        measure: measure,
                        query: AnalyticsQuery(
                          measure: measure.key,
                          interval: _interval,
                          schoolId: _schoolId,
                          from: _from == null ? null : _iso(_from!),
                          to: _to == null ? null : _iso(_to!),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SeriesView extends ConsumerWidget {
  const _SeriesView({required this.measure, required this.query});

  final AnalyticsMeasure measure;
  final AnalyticsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<AnalyticsSeries>(
      value: ref.watch(analyticsSeriesProvider(query)),
      onRetry: () => ref.invalidate(analyticsSeriesProvider(query)),
      data: (context, series) {
        if (series.isEmpty) return _Notice(_nothingToChart(series));

        final lines = SeriesLine.of(series, snapshot: measure.snapshot);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in lines) ...[_LineCard(series: series, line: line), const SizedBox(height: 16)],
            _PointsTable(series: series, lines: lines),
          ],
        );
      },
    );
  }

  /// Why a whole range has no figure - three different reasons, and the
  /// wrong one would send somebody looking for a fault that is not there.
  String _nothingToChart(AnalyticsSeries series) {
    if (measure.snapshot) {
      return 'No figures yet. ${measure.label} is recorded once a day, so this chart starts from the first day it '
          'was recorded.';
    }

    if (series.points.every((point) => point.workingDays == 0)) {
      return 'Nothing to chart in this period - the school did not run on any of these days.';
    }

    return 'Nothing recorded in this period yet. The school ran, but no ${measure.label.toLowerCase()} was recorded.';
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.series, required this.line});

  final AnalyticsSeries series;
  final SeriesLine line;

  /// A period in a sentence: "Oct 2026", or "week of 10/26".
  String _when(AnalyticsPoint point) {
    final label = periodLabel(point, series.interval);

    return series.interval == AnalyticsInterval.week ? 'week of $label' : label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = series.points;
    final known = [
      for (var i = 0; i < points.length; i++)
        if (line.values[i] != null) (point: points[i], value: line.values[i]!),
    ];

    final latest = known.lastOrNull;
    final previous = known.length > 1 ? known[known.length - 2] : null;
    final highest = known.isEmpty ? null : known.reduce((a, b) => b.value > a.value ? b : a);
    final lowest = known.isEmpty ? null : known.reduce((a, b) => b.value < a.value ? b : a);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.currencyCode == null ? series.label : '${series.label} (${line.currencyCode})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                if (latest != null) _Fact(label: 'Latest (${_when(latest.point)})', value: line.format(latest.value)),
                if (latest != null && previous != null)
                  _Fact(label: 'Change on the period before', value: line.formatChange(latest.value - previous.value)),
                if (highest != null)
                  _Fact(label: 'Highest (${_when(highest.point)})', value: line.format(highest.value)),
                if (lowest != null) _Fact(label: 'Lowest (${_when(lowest.point)})', value: line.format(lowest.value)),
                if (line.additive)
                  _Fact(label: 'Total in range', value: line.format(known.fold<double>(0, (sum, k) => sum + k.value))),
              ],
            ),
            const SizedBox(height: 16),
            TrendBarChart(
              maxValue: line.scale,
              bars: [
                for (var i = 0; i < points.length; i++)
                  TrendBar(
                    label: periodLabel(points[i], series.interval),
                    value: line.values[i],
                    valueLabel: line.format(line.values[i]),
                  ),
              ],
            ),
            if (known.length < points.length) ...[
              const SizedBox(height: 8),
              Text(
                'A dash is a period with no figure: no working day in it, nothing recorded yet, or - for attendance - '
                'no register taken.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Every point, exactly - what the bars round off, and what a screen reader
/// reads best.
class _PointsTable extends StatelessWidget {
  const _PointsTable({required this.series, required this.lines});

  final AnalyticsSeries series;
  final List<SeriesLine> lines;

  @override
  Widget build(BuildContext context) {
    final points = series.points;

    return Card(
      child: HorizontalScrollTable(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Period')),
            const DataColumn(label: Text('Working days'), numeric: true),
            for (final line in lines) DataColumn(label: Text(line.currencyCode ?? series.label), numeric: true),
          ],
          rows: [
            for (var i = points.length - 1; i >= 0; i--)
              DataRow(
                cells: [
                  DataCell(Text('${formatIsoDate(points[i].from)} to ${formatIsoDate(points[i].to)}')),
                  DataCell(Text('${points[i].workingDays}')),
                  for (final line in lines) DataCell(Text(line.format(line.values[i]))),
                ],
              ),
          ],
        ),
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
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
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
