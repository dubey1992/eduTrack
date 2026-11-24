import '../../../core/widgets/period_filter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../assessments/data/models/assessment.dart';
import '../application/my_teaching_providers.dart';
import '../../today/presentation/staff_words.dart';

/// The Marks part of the Teaching tab (docs/teacher-app.md, T5): the class
/// tests of the classes the teacher teaches, newest first, and the way to
/// set a new one.
class MarksTab extends ConsumerWidget {
  const MarksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tests = ref.watch(myTestsProvider);
    final notifier = ref.read(myTestsProvider.notifier);
    final colors = context.appColors;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('my-tests-new'),
        onPressed: () async {
          final created = await context.push<int>('/teaching/tests/new');
          if (created != null && context.mounted) context.push('/teaching/tests/$created');
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.staffNewTest),
      ),
      body: RefreshIndicator(
        key: const Key('my-tests-refresh'),
        onRefresh: () => ref.read(myTestsProvider.notifier).refresh(),
        child: ListView(
          key: const Key('my-tests-list'),
          // Room under the last card for the floating button.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(l10n.staffMarksIntro, style: TextStyle(color: colors.muted)),
            const SizedBox(height: 12),
            PeriodFilter(value: notifier.period, onChanged: notifier.setPeriod),
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
                    Text(l10n.staffEmptyTests(notifier.period.name), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      l10n.staffEmptyTestsBody,
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
                    child: Text(l10n.staffShowOlderTests),
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
    final l10n = context.l10n;

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
                      ? StatusBadge(label: l10n.staffDraft, tone: BadgeTone.warning)
                      : StatusBadge(label: l10n.staffPublished, tone: BadgeTone.success),
                ],
              ),
              const SizedBox(height: 2),
              Text('${test.subjectName} · ${test.classSectionName}', style: TextStyle(color: colors.muted)),
              Text(
                '${formatDate(test.assessmentDate)} · ${assessmentTypeLabel(l10n, test.type)} · '
                '${l10n.staffOutOf(test.maxMarksLabel)}',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
