import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/routing/app_nav.dart';
import '../../../auth/application/auth_notifier.dart';
import '../../../auth/application/school_clock_provider.dart';
import '../../../schools/application/school_list_notifier.dart';
import '../../application/analytics_notifier.dart';
import '../../data/models/analytics_series.dart';
import '../series_line.dart';
import 'trend_bar_chart.dart';

/// The dashboard's "Trends" row (docs/analytics.md): a few of the school's
/// figures over the last six months, each opening its full chart on the
/// Analytics page.
///
/// Six months rather than the Analytics page's twelve: each month is a
/// report run on the server, and the dashboard is the page everybody lands
/// on. Each card loads by itself, so a slow figure holds up nothing else.
class DashboardTrends extends ConsumerWidget {
  const DashboardTrends({super.key, required this.schoolId});

  /// The school the dashboard is showing; null for someone who has picked
  /// none (a Super Admin, or a Group Admin looking at the whole group).
  final int? schoolId;

  /// Which figures make the dashboard, in order, of those the person may
  /// chart - the ones a head teacher asks about first.
  static const featured = ['student_attendance_rate', 'staff_attendance_rate', 'fees_collected', 'active_students'];

  static const months = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    // Shown to exactly those the Analytics page is - the menu's own rule.
    final analytics = AppNav.findByPath('/analytics');
    if (user == null || analytics == null || !analytics.allows(user)) return const SizedBox.shrink();

    final measures = ref.watch(analyticsMeasuresProvider);

    // The dashboard's own figures matter more than these: a failure here
    // shrinks to one line rather than an error panel in the middle of it.
    if (measures.hasError) {
      return _Section(
        child: _Quiet(message: 'Trends could not be loaded.', onRetry: () => ref.invalidate(analyticsMeasuresProvider)),
      );
    }

    final available = measures.value;
    // Words rather than a spinner: these sit under the dashboard's own
    // figures and should not draw the eye while they arrive.
    if (available == null) return const _Section(child: _Quiet(message: 'Loading trends...'));

    final shown = [for (final key in featured) ...available.where((measure) => measure.key == key)];
    if (shown.isEmpty) return const SizedBox.shrink();

    // The whole group is not a figure the server charts yet, so someone
    // looking at it sees their own school's trends, named, until they pick a
    // branch. A Super Admin has no school of their own, and picks one.
    final schoolId = this.schoolId ?? (user.picksSchool ? user.schoolId : null);

    if (user.picksSchool && schoolId == null) {
      return const _Section(child: _Quiet(message: 'Pick a school above to see its trends.'));
    }

    final schools = user.picksSchool ? ref.watch(schoolListNotifierProvider).value : null;
    final schoolName = schools?.where((school) => school.id == schoolId).firstOrNull?.name;

    final today = ref.watch(schoolClockProvider).today;
    final from = DateTime(today.year, today.month - (months - 1));

    return _Section(
      schoolName: schoolName,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final measure in shown)
            _TrendCard(
              measure: measure,
              schoolId: schoolId,
              query: AnalyticsQuery(
                measure: measure.key,
                schoolId: schoolId,
                from: DateFormat('yyyy-MM-dd').format(from),
                to: DateFormat('yyyy-MM-dd').format(today),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.schoolName});

  final Widget child;

  /// Said when the trends are one school's under a dashboard showing more.
  final String? schoolName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                schoolName == null ? 'Trends, last 6 months' : 'Trends, last 6 months - $schoolName',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => context.go('/analytics'),
              icon: const Icon(Icons.bar_chart_outlined, size: 18),
              label: const Text('Open analytics'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.measure, required this.schoolId, required this.query});

  static const double width = 300;
  static const double height = 196;

  final AnalyticsMeasure measure;
  final int? schoolId;
  final AnalyticsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final series = ref.watch(analyticsSeriesProvider(query));

    return SizedBox(
      width: width,
      height: height,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // The full chart, on the same figure and school.
          onTap: () => context.go(
            Uri(
              path: '/analytics',
              queryParameters: {'measure': measure.key, 'school_id': ?schoolId?.toString()},
            ).toString(),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(measure.label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: series.when(
                    loading: () => const _Quiet(message: 'Loading...'),
                    error: (error, _) => _Quiet(
                      message: error is Failure ? error.message : 'Could not load this trend.',
                      onRetry: () => ref.invalidate(analyticsSeriesProvider(query)),
                    ),
                    data: (series) => _TrendFigures(measure: measure, series: series),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendFigures extends StatelessWidget {
  const _TrendFigures({required this.measure, required this.series});

  final AnalyticsMeasure measure;
  final AnalyticsSeries series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (series.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          measure.snapshot ? 'Recorded daily from now on - no figures yet.' : 'Nothing recorded yet.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    // Money has a line per currency. The card charts the first and states
    // the rest; never one figure added across them.
    final lines = SeriesLine.of(series, snapshot: measure.snapshot);
    final line = lines.first;
    final known = [for (final value in line.values) ?value];
    final latest = known.last;
    final previous = known.length > 1 ? known[known.length - 2] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(line.format(latest), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        Text(
          [
            if (previous != null) '${line.formatChange(latest - previous)} on the month before',
            if (lines.length > 1) '+${lines.length - 1} more ${lines.length > 2 ? 'currencies' : 'currency'}',
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TrendBarChart(
            compact: true,
            height: double.infinity,
            maxValue: line.scale,
            bars: [
              for (var i = 0; i < series.points.length; i++)
                TrendBar(
                  label: DateFormat('MMM').format(DateTime.parse(series.points[i].from)),
                  value: line.values[i],
                  valueLabel: line.format(line.values[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
        if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
