import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_nav.dart';
import '../../../auth/application/auth_notifier.dart';
import '../../application/analytics_notifier.dart';
import '../../data/models/early_warning.dart';

/// The dashboard's line about flagged students (docs/analytics.md, A3):
/// how many are at high risk and at risk, and the way to the list.
///
/// Says nothing when nobody is flagged, and nothing when it cannot load -
/// the dashboard's own figures matter more than a count that failed.
class EarlyWarningBanner extends ConsumerWidget {
  const EarlyWarningBanner({super.key, required this.schoolId});

  /// The school picked on the dashboard, for whoever picks one.
  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    final item = AppNav.findByPath('/early-warning');
    if (user == null || item == null || !item.allows(user)) return const SizedBox.shrink();

    final school = schoolId ?? (user.picksSchool ? user.schoolId : null);
    if (user.picksSchool && school == null) return const SizedBox.shrink();

    // One row is enough: the counts come with every page.
    final summary = ref.watch(earlyWarningProvider(EarlyWarningQuery(schoolId: school, perPage: 1))).value?.summary;
    if (summary == null || summary.flaggedCount == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final high = summary.highCount > 0;

    return Card(
      // Its own gap below, so a dashboard with nothing flagged has none.
      margin: const EdgeInsets.only(bottom: 12),
      color: high ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: high ? scheme.onErrorContainer : scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  if (summary.highCount > 0)
                    '${summary.highCount} ${summary.highCount == 1 ? 'student' : 'students'} at high risk',
                  if (summary.atRiskCount > 0) '${summary.atRiskCount} at risk',
                ].join(', '),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: high ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.go(
                Uri(
                  path: '/early-warning',
                  queryParameters: {
                    if (high) 'level': EarlyWarningLevel.high.apiValue,
                    'school_id': ?school?.toString(),
                  },
                ).toString(),
              ),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }
}
