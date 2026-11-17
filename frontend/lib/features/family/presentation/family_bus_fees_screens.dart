import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_day.dart';
import 'widgets/family_widgets.dart';

/// Today's day for the child on screen, for the tabs that read from it.
Widget _withToday(WidgetRef ref, Widget Function(FamilyToday day) builder) {
  final child = ref.watch(selectedChildProvider);
  if (child == null) {
    return const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show');
  }

  return ref
      .watch(familyTodayProvider(child.id))
      .when(
        skipLoadingOnRefresh: true,
        loading: () => const PlaceholderCards(count: 2),
        error: (error, _) =>
            FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyTodayProvider(child.id))),
        data: (fetched) => RefreshIndicator(
          onRefresh: () => ref.read(familyTodayProvider(child.id).notifier).refresh(),
          child: builder(fetched.data),
        ),
      );
}

/// Bus: the child's route and stop, and each of today's trips as it went
/// for them. The bus on a map is F4.
class FamilyBusScreen extends ConsumerWidget {
  const FamilyBusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _withToday(ref, (day) {
      final bus = day.bus;
      if (bus == null) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 60),
            FamilyEmptyView(
              icon: Icons.directions_bus_outlined,
              title: 'Not on a school bus',
              message: 'If your child should be, the school office can add them to a route.',
            ),
          ],
        );
      }

      final muted = context.appColors.muted;

      return ListView(
        key: const Key('family-bus'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          FamilyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardHeading(icon: Icons.route_rounded, title: 'Route and stop'),
                const SizedBox(height: 12),
                Text(bus.route, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (bus.stop != null) Text(bus.stop!, style: TextStyle(color: muted)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (bus.pickupTime != null)
                      Expanded(
                        child: _Time(label: 'Pick-up', time: formatClock(bus.pickupTime!)),
                      ),
                    if (bus.dropTime != null)
                      Expanded(
                        child: _Time(label: 'Drop', time: formatClock(bus.dropTime!)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _TripCard(title: 'To school', trip: bus.morning, closed: !day.isOpen),
          const SizedBox(height: 12),
          _TripCard(title: 'Home', trip: bus.afternoon, closed: !day.isOpen),
        ],
      );
    });
  }
}

class _Time extends StatelessWidget {
  const _Time({required this.label, required this.time});

  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.appColors.muted, fontSize: 12)),
        Text(time, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.title, required this.trip, required this.closed});

  final String title;
  final BusTrip? trip;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final trip = this.trip;
    final colour = switch (trip?.riderStatus) {
      'boarded' => colours.info,
      'dropped' => colours.success,
      'absent' => colours.warning,
      _ => colours.muted,
    };

    return FamilyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(icon: title == 'Home' ? Icons.home_rounded : Icons.school_rounded, title: title, colour: colour),
          const SizedBox(height: 10),
          Text(
            trip?.summary ?? (closed ? 'No school today' : 'Not started yet'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: trip == null ? colours.muted : null),
          ),
          if (trip?.boardedAt != null)
            Text('Boarded at ${formatClock(trip!.boardedAt!)}', style: TextStyle(color: colours.muted)),
          if (trip?.droppedAt != null)
            Text('Dropped at ${formatClock(trip!.droppedAt!)}', style: TextStyle(color: colours.muted)),
        ],
      ),
    );
  }
}
