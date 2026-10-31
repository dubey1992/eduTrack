import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../classes/presentation/quick_class_setup_dialog.dart';
import '../application/setup_guide_notifier.dart';
import '../data/models/setup_guide.dart';
import 'quick_departments_dialog.dart';

/// A new school's six setup steps, in the order they depend on each other
/// (docs/onboarding.md, O4). Each step opens the screen where it is done;
/// classes and departments can be added in one step from here.
class SetupGuideScreen extends ConsumerStatefulWidget {
  const SetupGuideScreen({super.key});

  @override
  ConsumerState<SetupGuideScreen> createState() => _SetupGuideScreenState();
}

class _SetupGuideScreenState extends ConsumerState<SetupGuideScreen> {
  @override
  void initState() {
    super.initState();
    // Whatever was added elsewhere since it was last read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(setupGuideNotifierProvider) is AsyncData) {
        ref.read(setupGuideNotifierProvider.notifier).refresh();
      }
    });
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _hide(SetupGuide guide) async {
    final notifier = ref.read(setupGuideNotifierProvider.notifier);
    if (guide.finished) {
      return _run(notifier.close, 'Setup guide closed. It stays under Setup Guide in the menu.');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hide the setup guide?'),
        content: Text(
          '${guide.done} of ${guide.total} steps are done. The guide leaves the dashboard for every admin of '
          '${guide.schoolName}; it stays under Setup Guide in the menu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hide')),
        ],
      ),
    );
    if (confirmed == true && mounted) await _run(notifier.close, 'Setup guide hidden from the dashboard.');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupGuideNotifierProvider);

    return AsyncValueView<SetupGuide>(
      value: state,
      onRetry: () => ref.invalidate(setupGuideNotifierProvider),
      data: (context, guide) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Progress(guide: guide),
                const SizedBox(height: 16),
                for (final (index, step) in guide.steps.indexed) ...[
                  _StepCard(number: index + 1, step: step, isNext: identical(step, guide.next)),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                Text('When you are ready', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final extra in guide.extras)
                        ListTile(
                          title: Text(extra.title),
                          subtitle: Text(extra.detail),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(extra.path),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: guide.closed
                      ? OutlinedButton.icon(
                          key: const Key('setup-guide-reopen'),
                          onPressed: () => _run(
                            ref.read(setupGuideNotifierProvider.notifier).reopen,
                            'The setup guide is back on the dashboard.',
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Show on the dashboard again'),
                        )
                      : TextButton.icon(
                          key: const Key('setup-guide-hide'),
                          onPressed: () => _hide(guide),
                          icon: Icon(guide.finished ? Icons.check : Icons.visibility_off_outlined, size: 18),
                          label: Text(guide.finished ? 'Close the guide' : 'Hide the guide'),
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

class _Progress extends StatelessWidget {
  const _Progress({required this.guide});

  final SetupGuide guide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              guide.finished ? '${guide.schoolName} is set up' : 'Set up ${guide.schoolName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              guide.finished
                  ? 'All six steps are done. Attendance, timetables and the rest are ready to use.'
                  : 'Six steps, in this order - each one needs the one before. ${guide.done} of ${guide.total} done.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: guide.done / guide.total, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends ConsumerWidget {
  const _StepCard({required this.number, required this.step, required this.isNext});

  final int number;
  final SetupStep step;
  final bool isNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocked = step.blockedBy != null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isNext ? scheme.primary : scheme.outlineVariant, width: isNext ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: step.done ? scheme.primary : scheme.surfaceContainerHighest,
              foregroundColor: step.done ? scheme.onPrimary : scheme.onSurfaceVariant,
              child: step.done ? const Icon(Icons.check, size: 18) : Text('$number'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(step.detail, style: theme.textTheme.bodyMedium),
                  if (step.summary != null) ...[
                    const SizedBox(height: 6),
                    Text(step.summary!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
                  ],
                  if (blocked) ...[const SizedBox(height: 6), Text(step.blockedBy!, style: theme.textTheme.bodySmall)],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (step.key == 'departments' && !step.done)
                        FilledButton.tonal(
                          onPressed: () => showDialog(context: context, builder: (_) => const QuickDepartmentsDialog()),
                          child: const Text('Add common departments'),
                        ),
                      if (step.key == 'classes' && !step.done && !blocked)
                        FilledButton.tonal(
                          onPressed: () async {
                            await showDialog(context: context, builder: (_) => const QuickClassSetupDialog());
                            await ref.read(setupGuideNotifierProvider.notifier).refresh();
                          },
                          child: const Text('Quick setup'),
                        ),
                      OutlinedButton(
                        onPressed: () => context.go(step.path),
                        child: Text(step.done ? 'Review' : 'Open ${step.title}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
