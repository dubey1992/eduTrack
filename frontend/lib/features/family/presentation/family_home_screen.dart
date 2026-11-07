import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/family_brand.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_day.dart';
import 'widgets/family_widgets.dart';

/// Home: the morning's questions answered without a tap - is my child in
/// school, where is the bus, is anything due, what did the school say
/// (docs/parent-student-app.md, "Today first").
class FamilyHomeScreen extends ConsumerWidget {
  const FamilyHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);

    if (child == null) {
      return const FamilyEmptyView(
        icon: Icons.family_restroom_rounded,
        title: 'No children to show',
        message: 'The school has no child linked to your number at the moment. Please contact the school office.',
      );
    }

    final today = ref.watch(familyTodayProvider(child.id));

    return today.when(
      skipLoadingOnRefresh: true,
      loading: () => const PlaceholderCards(count: 4),
      error: (error, _) => FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyTodayProvider(child.id))),
      data: (fetched) => RefreshIndicator(
        onRefresh: () async {
          await ref.read(familyTodayProvider(child.id).notifier).refresh();
          ref.invalidate(familyNoticesProvider);
        },
        child: _TodayList(fetched: fetched, childFirstName: child.firstName),
      ),
    );
  }
}

class _TodayList extends ConsumerWidget {
  const _TodayList({required this.fetched, required this.childFirstName});

  final Fetched<FamilyToday> fetched;
  final String childFirstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = fetched.data;
    final parent = ref.watch(familySessionProvider).value;
    final updated = DateFormat('h:mm a').format(fetched.at);

    return ListView(
      key: const Key('family-home'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text(
          '${_greeting(DateTime.now())}${parent == null ? '' : ', ${parent.firstName}'}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${DateFormat('EEEE').format(day.date)}, ${formatDate(day.date)}',
          style: TextStyle(color: context.appColors.muted),
        ),
        const SizedBox(height: 6),
        UpdatedLine(
          text: fetched.isStale ? 'No connection. Showing what was true at $updated.' : 'Updated $updated',
          stale: fetched.isStale,
        ),
        const SizedBox(height: 14),
        _AttendanceCard(day: day, name: childFirstName),
        if (day.bus != null) ...[const SizedBox(height: 12), _BusCard(bus: day.bus!)],
        if (day.fee != null) ...[const SizedBox(height: 12), _FeeCard(fee: day.fee!)],
        const SizedBox(height: 12),
        const _LatestNoticeCard(),
        if (day.periods.isNotEmpty) ...[const SizedBox(height: 12), _TimetableCard(day: day)],
      ],
    );
  }

  static String _greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';
}

/// In school or not, in plain words and the colour that goes with it.
class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.day, required this.name});

  final FamilyToday day;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    if (!day.isOpen) {
      return FamilyCard(
        key: const Key('family-today-closed'),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: colours.info, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No school today', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(day.holidayName ?? 'The school is closed today.', style: TextStyle(color: colours.muted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final mark = day.attendance?.mark ?? AttendanceMark.notMarked;
    final (colour, icon, words) = switch (mark) {
      AttendanceMark.present => (colours.success, Icons.check_circle_rounded, '$name is in school'),
      AttendanceMark.absent => (colours.danger, Icons.cancel_rounded, '$name was marked absent'),
      AttendanceMark.leave => (colours.info, Icons.event_busy_rounded, '$name is on leave today'),
      AttendanceMark.notMarked => (colours.muted, Icons.hourglass_top_rounded, 'Register not marked yet'),
    };

    return FamilyCard(
      key: const Key('family-today-attendance'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(icon: Icons.event_available_rounded, title: 'Attendance today'),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(icon, color: colour, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      words,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colour),
                    ),
                    if (mark == AttendanceMark.notMarked)
                      Text(
                        'The class teacher marks it in the morning.',
                        style: TextStyle(color: colours.muted, fontSize: 13),
                      ),
                    if (day.attendance?.remarks != null)
                      Text('Note: ${day.attendance!.remarks}', style: TextStyle(color: colours.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusCard extends StatelessWidget {
  const _BusCard({required this.bus});

  final TodayBus bus;

  @override
  Widget build(BuildContext context) {
    final trip = bus.trips.lastOrNull;
    final muted = context.appColors.muted;

    return FamilyCard(
      key: const Key('family-today-bus'),
      onTap: () => context.go('/bus'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            icon: Icons.directions_bus_rounded,
            title: 'School bus',
            colour: FamilyBrand.childColours[3],
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
          ),
          const SizedBox(height: 12),
          Text(
            trip?.summary ?? 'No trip has started today',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (bus.stop != null) bus.stop!,
              if (bus.pickupTime != null) 'pick-up ${formatClock(bus.pickupTime!)}',
            ].join(' · '),
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.fee});

  final NextFee fee;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return FamilyCard(
      key: const Key('family-today-fee'),
      onTap: () => context.go('/fees'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            icon: Icons.receipt_long_rounded,
            title: 'Next fee',
            colour: fee.isOverdue ? colours.danger : colours.warning,
            trailing: Icon(Icons.chevron_right_rounded, color: colours.muted),
          ),
          const SizedBox(height: 12),
          Text(
            formatCurrency(fee.amount, fee.currencyCode),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Text(
            '${fee.label} · ${fee.isOverdue ? 'was due' : 'due'} on ${formatDate(fee.dueDate)}',
            style: TextStyle(color: fee.isOverdue ? colours.danger : colours.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The newest message from the school, unread marked.
class _LatestNoticeCard extends ConsumerWidget {
  const _LatestNoticeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(familyNoticesProvider);
    final muted = context.appColors.muted;
    final latest = notices.value?.notices.firstOrNull;
    final unread = notices.value?.unreadCount ?? 0;

    return FamilyCard(
      key: const Key('family-today-notice'),
      onTap: () => context.push('/notices'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            icon: Icons.campaign_rounded,
            title: 'From the school',
            colour: FamilyBrand.childColours[1],
            trailing: unread > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$unread new', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  )
                : Icon(Icons.chevron_right_rounded, color: muted),
          ),
          const SizedBox(height: 12),
          if (notices.isLoading && latest == null)
            const ShapePlaceholder(height: 18)
          else if (latest == null)
            Text('No messages yet.', style: TextStyle(color: muted))
          else ...[
            Text(
              latest.title ?? latest.kindLabel,
              style: TextStyle(fontWeight: latest.read ? FontWeight.w500 : FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              latest.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Today's periods, the one on now picked out.
class _TimetableCard extends StatelessWidget {
  const _TimetableCard({required this.day});

  final FamilyToday day;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final primary = Theme.of(context).colorScheme.primary;

    return FamilyCard(
      key: const Key('family-today-timetable'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(icon: Icons.schedule_rounded, title: 'Today\'s classes'),
          const SizedBox(height: 8),
          for (final period in day.periods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      formatClock(period.startTime),
                      style: TextStyle(color: period.state == 'current' ? primary : muted, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      period.subject ?? 'Period ${period.number}',
                      style: TextStyle(
                        fontWeight: period.state == 'current' ? FontWeight.w700 : FontWeight.w500,
                        color: period.state == 'done' ? muted : null,
                      ),
                    ),
                  ),
                  if (period.state == 'current')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Now',
                        style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
