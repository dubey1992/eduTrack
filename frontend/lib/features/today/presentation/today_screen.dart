import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_notifier.dart';

/// The teacher's day (docs/teacher-app.md, T1).
///
/// T0 puts the screen in place: who you are, what day it is, and an honest
/// line about what comes next. T1 fills it with the periods in order and
/// what each still owes - the register, the report - from one call to the
/// server, which is where the school's clock and calendar live. Nothing
/// here guesses at either; the date below is the phone's, and says so by
/// being only a date.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    final colors = context.appColors;
    final today = DateFormat('EEEE, MMMM d, y').format(DateTime.now());
    final firstName = (user?.name ?? '').split(' ').first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          firstName.isEmpty ? 'Good day' : 'Good day, $firstName',
          key: const Key('today-greeting'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          today,
          key: const Key('today-date'),
          style: TextStyle(fontSize: 17, color: colors.muted),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: colors.muted),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Your day', style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Your periods for the day, with the register and the teaching report each one "
                  "still owes, arrive here with the next update of this app. Until then the "
                  "school's web portal has everything.",
                  key: const Key('today-placeholder'),
                  style: TextStyle(color: colors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
