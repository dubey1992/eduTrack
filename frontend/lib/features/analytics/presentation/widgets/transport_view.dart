import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../application/analytics_notifier.dart';
import '../../data/models/transport_overview.dart';

/// "Transport" on the Analytics page (docs/analytics.md, A6): each route
/// month by month - service, riders, on time at stops, trip length - and the
/// stops most often late, which is where a transport manager looks first.
class TransportView extends ConsumerWidget {
  const TransportView({super.key, required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<TransportOverview>(
      value: ref.watch(transportOverviewProvider(schoolId)),
      onRetry: () => ref.invalidate(transportOverviewProvider(schoolId)),
      data: (context, overview) {
        if (overview.routes.isEmpty) {
          return const _Notice('This school has no routes yet.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LateStopsCard(overview: overview),
            const SizedBox(height: 16),
            for (final route in overview.routes) ...[
              _RouteCard(route: route, lateAfter: overview.lateAfterMinutes),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }
}

String _month(String iso) => DateFormat('MMM yyyy').format(DateTime.parse(iso));

String _rate(double? rate) =>
    rate == null ? '-' : '${rate == rate.roundToDouble() ? rate.round() : rate.toStringAsFixed(1)}%';

String _minutes(double? minutes) =>
    minutes == null ? '-' : '${minutes == minutes.roundToDouble() ? minutes.round() : minutes.toStringAsFixed(1)} min';

class _LateStopsCard extends StatelessWidget {
  const _LateStopsCard({required this.overview});

  final TransportOverview overview;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Stops most often late',
      note:
          'Over the last twelve months. A bus is late at a stop when it arrives more than '
          '${overview.lateAfterMinutes} minutes after the stop\'s scheduled time; early is never late.',
      child: overview.lateStops.isEmpty
          ? const Text('No stop has been late.')
          : _Table(
              columns: const ['Stop', 'Route', 'Arrivals', 'Late', 'Late share', 'Average lateness'],
              rows: [
                for (final stop in overview.lateStops)
                  [
                    stop.stop,
                    stop.route,
                    '${stop.arrivals}',
                    '${stop.late}',
                    _rate(stop.lateRate),
                    _minutes(stop.averageMinutesLate),
                  ],
              ],
            ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.lateAfter});

  final RouteAnalytics route;
  final int lateAfter;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: route.route,
      note:
          'Days run are out of the school\'s working days. Riders on the bus are those marked boarded or '
          'dropped; no-shows were marked absent.',
      child: _Table(
        columns: const [
          'Month',
          'Days run',
          'Trips',
          'Cancelled',
          'Riders on the bus',
          'No-shows',
          'On time at stops',
          'Average lateness',
          'Average trip',
          'Longest trip',
        ],
        rows: [
          for (final month in route.months.reversed)
            [
              _month(month.from),
              '${month.daysRun} of ${month.workingDays}',
              '${month.tripsCompleted}',
              '${month.tripsCancelled}',
              month.ridersOnList == 0 ? '-' : '${month.boarded} of ${month.ridersOnList} (${_rate(month.boardedRate)})',
              '${month.absent}',
              month.arrivals == 0 ? '-' : '${_rate(month.onTimeRate)} of ${month.arrivals}',
              _minutes(month.averageMinutesLate),
              _minutes(month.averageMinutes),
              _minutes(month.longestMinutes),
            ],
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
