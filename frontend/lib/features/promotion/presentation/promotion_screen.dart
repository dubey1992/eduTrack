import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/section_header.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/promotion_history_notifier.dart';
import '../application/promotion_notifier.dart';
import '../application/promotion_target_provider.dart';
import '../data/models/promotion_batch.dart';
import '../data/models/promotion_preview.dart';
import 'promotion_batch_dialog.dart';
import '../../../core/widgets/dialog_message.dart';

/// Moving a class into the next year (docs/promotion.md).
///
/// Two steps, held as state rather than as two routes: choose the section
/// and the year, then read the roster and decide per student. Nothing is
/// written in either - the run is its own step and its own slice - so this
/// screen's whole job is to make the decision an informed one before
/// anything happens to a child's record.
class PromotionScreen extends ConsumerWidget {
  const PromotionScreen({super.key});

  /// Which of the three steps the screen is on. The run's result replaces
  /// the roster, because the roster describes a class that has just changed.
  Widget _step(PromotionState state) {
    if (state.hasRun) return _Done(batch: state.completed!);

    if (state.preview.isLoading || state.hasPreview || state.preview.hasError) {
      return _Review(state: state);
    }

    return _Choices(state: state);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(promotionNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Class Promotion',
          actions: [
            if (state.hasRun)
              FilledButton.icon(
                onPressed: () => ref.read(promotionNotifierProvider.notifier).startAgain(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Promote another class'),
              )
            else if (state.hasPreview)
              OutlinedButton.icon(
                onPressed: state.isRunning ? null : () => ref.read(promotionNotifierProvider.notifier).backToChoices(),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Change class'),
              ),
          ],
        ),
        Expanded(child: _step(state)),
      ],
    );
  }
}

/// Step one: which section, into which year.
class _Choices extends ConsumerWidget {
  const _Choices({required this.state});

  final PromotionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(promotionNotifierProvider.notifier);
    final sections = ref.watch(classSectionPickerProvider(null));
    final years = ref.watch(academicYearPickerProvider(null));
    final targets = ref.watch(promotionTargetSectionsProvider(state.toAcademicYearId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Promote a class into the next academic year. The next step shows every student with what '
            'would happen to them, and nothing is saved until you say so.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<int?>(
                  key: const Key('promotion-source'),
                  initialValue: state.classSectionId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Class to promote'),
                  items: [
                    for (final option in sections.value ?? const <ClassSectionOption>[])
                      DropdownMenuItem<int?>(value: option.id, child: Text(option.label)),
                  ],
                  onChanged: notifier.setSourceSection,
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<int?>(
                  key: const Key('promotion-year'),
                  initialValue: state.toAcademicYearId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Into academic year'),
                  items: [
                    for (final year in years.value ?? const <AcademicYear>[])
                      DropdownMenuItem<int?>(value: year.id, child: Text(year.name)),
                  ],
                  onChanged: notifier.setTargetYear,
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<int?>(
                  key: const Key('promotion-target'),
                  initialValue: state.toClassSectionId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Into class (optional)',
                    // Allowed to wrap: at this width the line was being
                    // clipped to "...be suggest…", which helps nobody.
                    helperText: 'Or let the class above be suggested',
                    helperMaxLines: 2,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Suggest one for me')),
                    for (final option in targets.value ?? const <ClassSectionOption>[])
                      DropdownMenuItem<int?>(value: option.id, child: Text(option.label)),
                  ],
                  onChanged: notifier.setTargetSection,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: state.canPreview ? notifier.loadPreview : null,
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: const Text('Review students'),
          ),
          const SizedBox(height: 32),
          const _History(),
        ],
      ),
    );
  }
}

/// What has been promoted already. Shown under the first step, because the
/// question "did somebody already do this" belongs before the doing.
class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(promotionHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Promotions already run', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        AsyncValueView<PagedList<PromotionBatch>>(
          value: history,
          onRetry: () => ref.read(promotionHistoryProvider.notifier).refresh(),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) => Text(
            'No class has been promoted yet.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          data: (context, page) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HorizontalScrollTable(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('When')),
                    DataColumn(label: Text('Class')),
                    DataColumn(label: Text('Into')),
                    DataColumn(label: Text('Students')),
                    DataColumn(label: Text('Outcomes')),
                    DataColumn(label: Text('Run by')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final batch in page.items)
                      DataRow(
                        cells: [
                          DataCell(Text(batch.runAt == null ? '-' : formatDate(batch.runAt!))),
                          DataCell(Text('${batch.fromClassSectionName} · ${batch.fromAcademicYearName}')),
                          DataCell(
                            Text('${batch.toClassSectionName ?? 'Finished school'} · ${batch.toAcademicYearName}'),
                          ),
                          DataCell(Text('${batch.studentCount}')),
                          DataCell(
                            Text(
                              '${batch.promotedCount} up · ${batch.retainedCount} held · '
                              '${batch.graduatedCount} out · ${batch.leftCount} left',
                            ),
                          ),
                          DataCell(Text(batch.runByName)),
                          DataCell(
                            TextButton(
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => PromotionBatchDialog(batchId: batch.id),
                              ),
                              child: const Text('View'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              PaginationControls(
                currentPage: page.currentPage,
                lastPage: page.lastPage,
                total: page.total,
                perPage: page.perPage,
                onPageChanged: (value) => ref.read(promotionHistoryProvider.notifier).setPage(value),
                onPerPageChanged: (value) => ref.read(promotionHistoryProvider.notifier).setPerPage(value),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Step two: the roster, and a decision per student.
class _Review extends ConsumerWidget {
  const _Review({required this.state});

  final PromotionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<PromotionPreview?>(
      value: state.preview,
      onRetry: () => ref.read(promotionNotifierProvider.notifier).loadPreview(),
      isEmpty: (preview) => preview == null,
      emptyBuilder: (context) => const SizedBox.shrink(),
      data: (context, preview) => _Roster(state: state, preview: preview!),
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({required this.state, required this.preview});

  final PromotionState state;
  final PromotionPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(promotionNotifierProvider.notifier);
    final students = state.visibleStudents;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Journey(preview: preview),
          if (preview.isGraduating) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.school_outlined,
              text:
                  'There is no class above ${preview.from.schoolClassName} in ${preview.to.academicYearName}, '
                  'so these students finish school.',
            ),
          ],
          if (!preview.canRun) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.info_outline,
              isWarning: true,
              text: preview.cannotRunReason == 'NOTHING_TO_PROMOTE'
                  ? 'There is nobody in this class to promote.'
                  : 'Nobody in this class can be promoted: they all have a place in '
                        '${preview.to.academicYearName} already.',
            ),
          ],
          const SizedBox(height: 16),
          _Counts(counts: state.counts),
          const SizedBox(height: 16),
          _Toolbar(state: state),
          const SizedBox(height: 12),
          if (students.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  preview.students.isEmpty ? 'This class has no students.' : 'No student matches that search.',
                ),
              ),
            )
          else
            HorizontalScrollTable(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Roll')),
                  DataColumn(label: Text('Student')),
                  DataColumn(label: Text('Admission')),
                  DataColumn(label: Text('Average')),
                  DataColumn(label: Text('Attendance')),
                  DataColumn(label: Text('Outcome')),
                  DataColumn(label: Text('Notes')),
                ],
                rows: [
                  for (final student in students)
                    DataRow(
                      cells: [
                        DataCell(Text(student.rollNumber ?? '-')),
                        DataCell(Text(student.name)),
                        DataCell(Text(student.admissionNumber)),
                        DataCell(Text(student.averagePercentage == null ? '-' : '${student.averagePercentage}%')),
                        DataCell(
                          Text(
                            student.attendancePercentage == null
                                ? '-'
                                : '${student.attendancePercentage!.toStringAsFixed(1)}%',
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<PromotionOutcome>(
                              key: Key('outcome-${student.studentId}'),
                              initialValue: state.outcomeFor(student),
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true),
                              items: [
                                for (final outcome in PromotionOutcome.values)
                                  DropdownMenuItem(value: outcome, child: Text(outcome.label)),
                              ],
                              // A student who already has a place in the
                              // target year cannot be moved into it again, so
                              // the row is shown and not offered.
                              onChanged: student.isBlocked
                                  ? null
                                  : (outcome) {
                                      if (outcome != null) notifier.setOutcome(student.studentId, outcome);
                                    },
                            ),
                          ),
                        ),
                        DataCell(_Note(student: student)),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (state.error != null) ...[
            _Notice(icon: Icons.error_outline, isWarning: true, text: state.error!),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              FilledButton.icon(
                onPressed: preview.canRun && !state.isRunning ? () => _confirm(context, ref, state, preview) : null,
                icon: state.isRunning
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Promote this class'),
              ),
              const SizedBox(width: 12),
              Text(
                'Nothing has been saved yet.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The last thing between a decision and a child's record: the counts
  /// spelled out, in the app's own dialog.
  Future<void> _confirm(BuildContext context, WidgetRef ref, PromotionState state, PromotionPreview preview) async {
    final counts = state.counts;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promote this class?'),
        content: DialogMessage(
          '${preview.from.classSectionName} moves into ${preview.to.academicYearName}.\n\n'
          '${counts[PromotionOutcome.promote]} promoted to ${preview.to.classSectionName ?? 'the next class'}, '
          '${counts[PromotionOutcome.retain]} retained, '
          '${counts[PromotionOutcome.graduate]} graduated, '
          '${counts[PromotionOutcome.leave]} left out.\n\n'
          'Each student keeps every past year on record. This cannot be undone from here: '
          'correcting it afterwards means moving those students by hand.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Promote')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ran = await ref.read(promotionNotifierProvider.notifier).run();

    if (ran) {
      // The history under the first step is now a batch out of date.
      ref.invalidate(promotionHistoryProvider);
      messenger.showSnackBar(const SnackBar(content: Text('The class has been promoted.')));
    }
  }
}

/// Step three: what the run did.
class _Done extends ConsumerWidget {
  const _Done({required this.batch});

  final PromotionBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Notice(
            icon: Icons.check_circle_outline,
            text:
                '${batch.fromClassSectionName} has moved into ${batch.toAcademicYearName}. '
                '${batch.studentCount} ${batch.studentCount == 1 ? 'student' : 'students'} in the batch.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Promoted: ${batch.promotedCount}')),
              Chip(label: Text('Retained: ${batch.retainedCount}')),
              Chip(label: Text('Graduated: ${batch.graduatedCount}')),
              Chip(label: Text('Left out: ${batch.leftCount}')),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => PromotionBatchDialog(batchId: batch.id),
            ),
            icon: const Icon(Icons.list_alt_outlined, size: 18),
            label: const Text('See what happened to each student'),
          ),
        ],
      ),
    );
  }
}

/// "Grade 8 A · 2026-27 → Grade 9 A · 2027-28", with the target marked when
/// the backend picked it rather than the school.
class _Journey extends StatelessWidget {
  const _Journey({required this.preview});

  final PromotionPreview preview;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.from.classSectionName ?? '-', style: Theme.of(context).textTheme.titleMedium),
            Text(preview.from.academicYearName, style: muted),
          ],
        ),
        const Icon(Icons.arrow_forward),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.to.classSectionName ?? 'Finishing school', style: Theme.of(context).textTheme.titleMedium),
            Text(preview.to.academicYearName, style: muted),
          ],
        ),
        if (preview.to.isSuggested && preview.to.classSectionName != null)
          Chip(label: const Text('Suggested'), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.counts});

  final Map<PromotionOutcome, int> counts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final outcome in PromotionOutcome.values)
          Chip(label: Text('${outcome.label}: ${counts[outcome] ?? 0}'), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.state});

  final PromotionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(promotionNotifierProvider.notifier);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextFormField(
            key: const Key('promotion-search'),
            initialValue: state.search,
            decoration: const InputDecoration(
              labelText: 'Search name or admission number',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: notifier.setSearch,
          ),
        ),
        OutlinedButton(
          onPressed: () => notifier.setOutcomeForVisible(PromotionOutcome.promote),
          child: const Text('Promote all'),
        ),
        OutlinedButton(
          onPressed: () => notifier.setOutcomeForVisible(PromotionOutcome.graduate),
          child: const Text('Graduate all'),
        ),
        TextButton(onPressed: notifier.resetOutcomes, child: const Text('Reset to suggestions')),
      ],
    );
  }
}

/// Why this row reads the way it does: blocked, or flagged by its marks.
class _Note extends StatelessWidget {
  const _Note({required this.student});

  final PromotionStudent student;

  @override
  Widget build(BuildContext context) {
    if (student.isBlocked) {
      return SizedBox(
        width: 260,
        child: Text(
          student.blockedReason ?? 'Already in the next year.',
          style: TextStyle(color: context.appColors.danger),
        ),
      );
    }

    if (student.suggestionReason != null) {
      return SizedBox(
        width: 260,
        child: Text(student.suggestionReason!, style: TextStyle(color: context.appColors.warning)),
      );
    }

    return const SizedBox.shrink();
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.isWarning = false});

  final IconData icon;
  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? context.appColors.warning : Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
