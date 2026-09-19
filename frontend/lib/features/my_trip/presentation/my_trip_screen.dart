import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../application/my_routes_notifier.dart';
import '../application/trip_mark_queue.dart';
import '../data/models/my_route.dart';
import 'widgets/route_card.dart';
import 'widgets/running_trip_view.dart';
import 'widgets/sync_banner.dart';

/// The bus attendant's screen (docs/maps.md, "The Bus Attendant"): today's
/// trips on their routes, and the trip they are running - start, reach each
/// stop, mark each child, call a parent, end, share location. Built for a
/// phone held on a moving bus: big buttons, one column, and no waiting on
/// signal for anything but starting a trip.
class MyTripScreen extends ConsumerStatefulWidget {
  const MyTripScreen({super.key});

  @override
  ConsumerState<MyTripScreen> createState() => _MyTripScreenState();
}

class _MyTripScreenState extends ConsumerState<MyTripScreen> {
  /// The trip on screen, or null for the list of routes.
  int? _openTripId;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in front after the phone was put away: signal may be back too.
    _lifecycle = AppLifecycleListener(onResume: _sendWaitingMarks);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendWaitingMarks());
  }

  void _sendWaitingMarks() {
    if (mounted) ref.read(tripMarkQueueProvider.notifier).retryNow();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripId = _openTripId;

    return Column(
      children: [
        const SyncBanner(),
        Expanded(
          child: tripId == null
              ? _RoutesView(onOpenTrip: (id) => setState(() => _openTripId = id))
              : RunningTripView(
                  key: ValueKey(tripId),
                  tripId: tripId,
                  onBack: () => setState(() => _openTripId = null),
                ),
        ),
      ],
    );
  }
}

class _RoutesView extends ConsumerWidget {
  const _RoutesView({required this.onOpenTrip});

  final ValueChanged<int> onOpenTrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(myRoutesProvider);

    return AsyncValueView<MyRoutesDay>(
      value: routes,
      onRetry: () => ref.read(myRoutesProvider.notifier).refresh(),
      isEmpty: (day) => day.routes.isEmpty,
      emptyBuilder: (context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No route is assigned to you yet. Ask your school office to add you to a route.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (context, day) => RefreshIndicator(
        onRefresh: () => ref.read(myRoutesProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_formatDay(day.date), style: Theme.of(context).textTheme.headlineSmall),
            if (day.fromCache)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No signal - showing your routes as last saved on this phone.',
                  style: TextStyle(color: context.appColors.muted, fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 16),
            for (final route in day.routes) RouteCard(route: route, onOpenTrip: onOpenTrip),
          ],
        ),
      ),
    );
  }

  /// "Saturday, September 19, 2026" - the school's today, as the server said it.
  String _formatDay(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    return date == null ? isoDate : DateFormat('EEEE, MMMM d, y').format(date);
  }
}
