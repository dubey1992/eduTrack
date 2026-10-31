import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/setup_guide_notifier.dart';
import '../data/models/setup_guide.dart';

/// The setup guide's progress on a School Admin's dashboard, until it is
/// finished or hidden (docs/onboarding.md, O4). A brand-new school - no
/// academic year yet - is taken to the guide itself, once a session.
///
/// The figures below it are the dashboard's own, so this card never stands
/// in their way: while it loads, or if it cannot load, it shows nothing.
class SetupGuideCard extends ConsumerWidget {
  const SetupGuideCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<SetupGuide>>(setupGuideNotifierProvider, (_, next) {
      final guide = next.value;
      if (guide == null || guide.closed || !guide.justStarted) return;
      if (ref.read(setupGuideAutoOpenedProvider)) return;

      ref.read(setupGuideAutoOpenedProvider.notifier).markOpened();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/setup-guide');
      });
    }, onError: (error, _) => debugPrint('Setup guide could not be read: $error'));

    final guide = ref.watch(setupGuideNotifierProvider).value;
    if (guide == null || guide.closed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final next = guide.next;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('setup-guide-card'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                guide.finished ? '${guide.schoolName} is set up' : 'Set up your school',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                guide.finished
                    ? 'All six steps are done.'
                    : '${guide.done} of ${guide.total} steps done. Next: ${next?.title}.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: guide.done / guide.total, minHeight: 6),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => context.go('/setup-guide'),
                    child: Text(guide.finished ? 'Open the guide' : 'Continue setup'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
