import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/examination_providers.dart';
import '../data/examination_repository.dart';
import '../data/models/examination.dart';
import 'admit_cards_tab.dart';
import 'date_sheet_editor.dart';
import 'examination_access.dart';
import 'examination_dialog.dart';
import 'examination_list_screen.dart';

/// One exam: its details, its date sheet and its admit cards
/// (docs/examinations.md).
class ExaminationDetailScreen extends ConsumerWidget {
  const ExaminationDetailScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(examinationProvider(examId));

    return AsyncValueView<Examination>(
      value: state,
      onRetry: () => ref.invalidate(examinationProvider(examId)),
      data: (context, exam) => _Detail(exam: exam),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.exam});

  final Examination exam;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool _publishing = false;

  Examination get exam => widget.exam;

  Future<void> _publish() async {
    if (_publishing) return;
    final next = exam.version + 1;
    final confirmed = await confirmDialog(
      context,
      title: exam.isPublished ? 'Publish version $next?' : 'Publish the admit cards?',
      message: exam.isPublished
          ? 'Cards will print the changed date sheet as version $next. Version ${exam.version} stays on record and '
                'can still be reprinted.'
          : 'Cards become available to print, and to parents in the Family app. Later changes need publishing again '
                'as a new version.',
      confirmLabel: 'Publish',
    );
    if (!confirmed || !mounted) return;

    setState(() => _publishing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(examinationProvider(exam.id).notifier).publish();
      messenger.showSnackBar(SnackBar(content: Text('Published as version $next.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Delete this draft?',
      message: '"${exam.name}" and its date sheet will be deleted. It was never published, so no card was issued.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(examinationRepositoryProvider).delete(exam.id);
      ref.invalidate(examinationListProvider);
      if (mounted) context.go('/examinations');
      messenger.showSnackBar(const SnackBar(content: Text('Draft deleted.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = canManageExams(ref.watch(authNotifierProvider).value);
    final colors = context.appColors;
    final canPublish = canManage && exam.paperCount > 0 && (!exam.isPublished || exam.hasUnpublishedChanges);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'All exams',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => context.go('/examinations'),
                        ),
                        Text(exam.name, style: Theme.of(context).textTheme.titleLarge),
                        StatusBadge(key: const Key('exam-status'), label: exam.statusLabel, tone: examTone(exam)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: Text(
                        [
                          exam.academicYearName,
                          ?exam.academicTermName,
                          if (exam.centre != null && exam.centre!.isNotEmpty) exam.centre!,
                          if (exam.reportingTime != null) 'Reporting ${formatClock(exam.reportingTime!)}',
                          if (exam.blockOnFeeDues) 'Cards held for overdue fees',
                        ].join(' · '),
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                if (canManage)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('exam-edit'),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => ExaminationDialog(exam: exam),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit details'),
                      ),
                      if (!exam.isPublished)
                        TextButton.icon(
                          key: const Key('exam-delete'),
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete draft'),
                        ),
                      FilledButton.icon(
                        key: const Key('exam-publish'),
                        onPressed: canPublish && !_publishing ? _publish : null,
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: Text(exam.isPublished ? 'Publish version ${exam.version + 1}' : 'Publish'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (exam.hasUnpublishedChanges)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                'The date sheet or details changed after version ${exam.version} was published. Cards still print '
                'version ${exam.version} until you publish again.',
                key: const Key('exam-unpublished-note'),
                style: TextStyle(color: colors.warning, fontSize: 13),
              ),
            ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: Key('exam-tab-sheet'), text: 'Date sheet'),
              Tab(key: Key('exam-tab-cards'), text: 'Admit cards'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                DateSheetEditor(exam: exam, canEdit: canManage),
                AdmitCardsTab(exam: exam, canManage: canManage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
