import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/module_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_notifier.dart';
import '../../check_in/application/check_in_notifier.dart';
import '../../check_in/data/models/my_attendance_day.dart';
import '../../check_in/presentation/check_in_card.dart';

/// Home for everybody in the school who does not teach a timetable - office
/// staff, accountants, transport managers, the school's administrators
/// (docs/staff-check-in.md).
///
/// A teacher's day is periods and registers; theirs, in this app, is
/// arriving and leaving. So: who they are, the school's date, and the
/// check-in card - or, on a day there is nothing to check in to, why.
/// Under it, where the rest of their app is: the Leave and Pay tabs where
/// the school uses them, and the bell for messages.
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(checkInProvider).value;
    final colors = context.appColors;
    final user = ref.watch(authNotifierProvider).value;
    final firstName = (user?.name ?? '').split(' ').first;

    return RefreshIndicator(
      key: const Key('staff-home-refresh'),
      onRefresh: () => ref.read(checkInProvider.notifier).refresh(),
      child: ListView(
        key: const Key('staff-home'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            firstName.isEmpty ? 'Good day' : 'Good day, $firstName',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (day != null) ...[
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE, MMMM d, y').format(day.date),
              key: const Key('staff-home-date'),
              style: TextStyle(fontSize: 17, color: colors.muted),
            ),
          ],
          const SizedBox(height: 16),
          const CheckInCard(),
          if (day != null && day.hidden) ...[_WhyNoCheckIn(day: day), const SizedBox(height: 12)],
          // The office finding a student (7.4), where its role may see them.
          if (user?.canView(AppModules.students) ?? false)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('staff-home-open-students'),
                onPressed: () => context.push('/find-student'),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Find a student'),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  whereThingsAre(
                    leave: user?.canView(AppModules.leave) ?? false,
                    pay: user?.moduleOn(AppModules.payroll) ?? false,
                  ),
                  key: const Key('staff-home-where-note'),
                  style: TextStyle(fontSize: 13, color: colors.muted, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the rest of this app is, naming only the tabs this school has -
/// the old note promised leave and payslips "next" after they had arrived
/// (docs/mobile-apps-review.md, 7.6).
String whereThingsAre({required bool leave, required bool pay}) {
  final tabs = switch ((leave, pay)) {
    (true, true) => 'Your leave and payslips are in the Leave and Pay tabs below. ',
    (true, false) => 'Your leave is in the Leave tab below. ',
    (false, true) => 'Your payslips are in the Pay tab below. ',
    (false, false) => '',
  };

  return "${tabs}The school's messages are under the bell at the top.";
}

/// On a day the check-in card has nothing to offer, the reason in words -
/// so the screen is never just a greeting.
class _WhyNoCheckIn extends StatelessWidget {
  const _WhyNoCheckIn({required this.day});

  final MyAttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = !day.isOpen
        ? (Icons.event_busy_outlined, 'No school today', 'The school is closed, so there is nothing to check in to.')
        : day.onLeave
        ? (Icons.beach_access_outlined, 'You are on leave today', 'Nothing to check in to while you are away.')
        : (
            Icons.apartment_outlined,
            'Attendance is marked in the office',
            'Your school records staff attendance itself rather than from the app.',
          );

    return Card(
      key: const Key('staff-home-no-check-in'),
      child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(body)),
    );
  }
}
