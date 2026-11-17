import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/paginated_response.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/examination_providers.dart';
import '../data/models/examination.dart';
import 'examination_access.dart';
import 'examination_dialog.dart';

/// The exams of the year in view, each with its state and dates
/// (docs/examinations.md). Opening one leads to its date sheet and cards.
class ExaminationListScreen extends ConsumerWidget {
  const ExaminationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(examinationListProvider);
    final canManage = canManageExams(ref.watch(authNotifierProvider).value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Examinations',
          actions: [
            if (canManage)
              FilledButton.icon(
                key: const Key('exam-new'),
                onPressed: () async {
                  final created = await showDialog<Examination>(
                    context: context,
                    builder: (_) => const ExaminationDialog(),
                  );
                  if (created != null && context.mounted) context.go('/examinations/${created.id}');
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New exam'),
              ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PaginatedResponse<Examination>>(
            value: state,
            onRetry: () => ref.invalidate(examinationListProvider),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => Center(
              key: const Key('exams-empty'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  canManage
                      ? 'No exams this year yet. Create one, add its date sheet, then publish the admit cards.'
                      : 'No exams this year yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (context, page) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _ExamCard(exam: page.items[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});

  final Examination exam;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dates = exam.firstDate == null
        ? 'No papers yet'
        : exam.firstDate == exam.lastDate
        ? formatIsoDate(exam.firstDate)
        : '${formatIsoDate(exam.firstDate)} to ${formatIsoDate(exam.lastDate)}';

    return Card(
      child: InkWell(
        key: Key('exam-${exam.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/examinations/${exam.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(exam.name, style: Theme.of(context).textTheme.titleMedium),
                        StatusBadge(label: exam.statusLabel, tone: examTone(exam)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [exam.academicYearName, ?exam.academicTermName, dates].join(' · '),
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${exam.paperCount} paper${exam.paperCount == 1 ? '' : 's'} across '
                      '${exam.classCount} class${exam.classCount == 1 ? '' : 'es'}',
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

BadgeTone examTone(Examination exam) {
  if (!exam.isPublished) return BadgeTone.neutral;
  return exam.hasUnpublishedChanges ? BadgeTone.warning : BadgeTone.success;
}
