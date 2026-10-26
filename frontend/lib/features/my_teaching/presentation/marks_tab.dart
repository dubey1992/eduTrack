import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../assessments/data/models/assessment.dart';
import '../application/my_teaching_providers.dart';

/// The Marks part of the Teaching tab (docs/teacher-app.md, T5): the class
/// tests of the classes the teacher teaches, newest first, and the way to
/// set a new one.
class MarksTab extends ConsumerWidget {
  const MarksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tests = ref.watch(myTestsProvider);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('my-tests-new'),
        onPressed: () async {
          final created = await context.push<int>('/teaching/tests/new');
          if (created != null && context.mounted) context.push('/teaching/tests/$created');
        },
        icon: const Icon(Icons.add),
        label: const Text('New test'),
      ),
      body: RefreshIndicator(
        key: const Key('my-tests-refresh'),
        onRefresh: () => ref.read(myTestsProvider.notifier).refresh(),
        child: ListView(
          key: const Key('my-tests-list'),
          // Room under the last card for the floating button.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              'Class tests for the classes you teach. Open one to enter marks; '
              'publish when everyone is marked.',
              style: TextStyle(color: colors.muted),
            ),
            const SizedBox(height: 16),
            if (!tests.hasValue)
              AsyncValueView<MyTests>(
                value: tests,
                onRetry: () => ref.read(myTestsProvider.notifier).retry(),
                data: (context, value) => const SizedBox.shrink(),
              )
            else if (tests.requireValue.items.isEmpty)
              Padding(
                key: const Key('my-tests-empty'),
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined, size: 48, color: colors.muted),
                    const SizedBox(height: 12),
                    const Text('No class tests yet.', textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      'Tap New test to set one for a class you teach.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted),
                    ),
                  ],
                ),
              )
            else ...[
              for (final test in tests.requireValue.items) ...[_TestCard(test: test), const SizedBox(height: 10)],
              if (tests.requireValue.hasMore)
                Center(
                  child: TextButton(
                    key: const Key('my-tests-more'),
                    onPressed: () => ref.read(myTestsProvider.notifier).loadMore(),
                    child: const Text('Show older tests'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test});

  final Assessment test;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Card(
      key: Key('my-test-${test.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/teaching/tests/${test.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      test.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  test.isDraft
                      ? const StatusBadge(label: 'Draft', tone: BadgeTone.warning)
                      : const StatusBadge(label: 'Published', tone: BadgeTone.success),
                ],
              ),
              const SizedBox(height: 2),
              Text('${test.subjectName} · ${test.classSectionName}', style: TextStyle(color: colors.muted)),
              Text(
                '${formatDate(test.assessmentDate)} · ${test.type.label} · out of ${test.maxMarksLabel}',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
