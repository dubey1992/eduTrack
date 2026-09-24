import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../../imports/presentation/bulk_import_button.dart';
import '../application/assessment_list_notifier.dart';
import '../data/models/assessment.dart';
import 'assessment_dialog.dart';
import 'marks_sheet_dialog.dart';

/// The class tests a school has set (docs/assessments.md).
///
/// A teacher sees the tests of the sections and subjects the timetable gives
/// them, an HOD their department's subjects, an administrator the school.
/// That narrowing is the server's, not this screen's: the list simply shows
/// what came back.
class AssessmentListScreen extends ConsumerStatefulWidget {
  const AssessmentListScreen({super.key});

  @override
  ConsumerState<AssessmentListScreen> createState() => _AssessmentListScreenState();
}

class _AssessmentListScreenState extends ConsumerState<AssessmentListScreen> {
  int? _sectionFilter;
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assessmentListNotifierProvider);
    final actor = ref.watch(authNotifierProvider).value;
    final canManage = actor?.canManage(AppModules.assessments) ?? false;
    final administers = canManage && actor != null && actor.role.administersSchool;
    final sections = ref.watch(classSectionPickerProvider(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Class Tests',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AssessmentDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Test'),
              ),
            // A file of tests crosses classes, so it is an administrator's
            // tool: a teacher sets their own one at a time, where the
            // timetable answers for each (docs/assessments.md).
            if (administers)
              BulkImportButton(
                type: 'assessments',
                title: 'Class Tests',
                onImported: () => ref.read(assessmentListNotifierProvider.notifier).refresh(),
              ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int?>(
                initialValue: _sectionFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Class', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All classes')),
                  for (final option in sections.value ?? const <ClassSectionOption>[])
                    DropdownMenuItem<int?>(value: option.id, child: Text(option.label)),
                ],
                onChanged: (value) {
                  setState(() => _sectionFilter = value);
                  ref.read(assessmentListNotifierProvider.notifier).setSectionFilter(value);
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String?>(
                initialValue: _statusFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
                  for (final status in AssessmentStatus.values)
                    DropdownMenuItem<String?>(value: status.apiValue, child: Text(status.label)),
                ],
                onChanged: (value) {
                  setState(() => _statusFilter = value);
                  ref.read(assessmentListNotifierProvider.notifier).setStatusFilter(value);
                },
              ),
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<Assessment>>(
            value: state,
            onRetry: () => ref.read(assessmentListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No class tests yet.', textAlign: TextAlign.center),
              ),
            ),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _AssessmentsMobile(assessments: page.items, canManage: canManage),
                      desktop: (context) => _AssessmentsDesktop(assessments: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(assessmentListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(assessmentListNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AssessmentsMobile extends StatelessWidget {
  const _AssessmentsMobile({required this.assessments, required this.canManage});

  final List<Assessment> assessments;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: assessments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final assessment = assessments[index];

        return Card(
          child: ListTile(
            title: Text(assessment.title),
            isThreeLine: true,
            subtitle: Text(
              '${assessment.classSectionName} · ${assessment.subjectName}\n'
              '${assessment.type.label} · out of ${assessment.maxMarksLabel} · ${formatDate(assessment.assessmentDate)}',
            ),
            trailing: _StatusFor(assessment: assessment),
            // On a phone the thing a teacher came for is the marks; editing
            // the test itself is a desk job.
            onTap: () => showDialog(
              context: context,
              builder: (_) => MarksSheetDialog(assessment: assessment, canManage: canManage),
            ),
          ),
        );
      },
    );
  }
}

class _AssessmentsDesktop extends StatelessWidget {
  const _AssessmentsDesktop({required this.assessments, required this.canManage});

  final List<Assessment> assessments;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Title')),
              DataColumn(label: Text('Class')),
              DataColumn(label: Text('Subject')),
              DataColumn(label: Text('Kind')),
              DataColumn(label: Text('Out of')),
              DataColumn(label: Text('Term')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final assessment in assessments)
                DataRow(
                  cells: [
                    DataCell(Text(formatDate(assessment.assessmentDate))),
                    DataCell(Text(assessment.title)),
                    DataCell(Text(assessment.classSectionName)),
                    DataCell(Text(assessment.subjectName)),
                    DataCell(Text(assessment.type.label)),
                    DataCell(Text(assessment.maxMarksLabel)),
                    DataCell(Text(assessment.termName)),
                    DataCell(_StatusFor(assessment: assessment)),
                    DataCell(_Actions(assessment: assessment, canManage: canManage)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusFor extends StatelessWidget {
  const _StatusFor({required this.assessment});

  final Assessment assessment;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: assessment.status.label,
      tone: assessment.isDraft ? BadgeTone.neutral : BadgeTone.success,
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.assessment, required this.canManage});

  final Assessment assessment;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marks = TextButton(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => MarksSheetDialog(assessment: assessment, canManage: canManage),
      ),
      child: const Text('Marks'),
    );

    // A published result has already reached guardians. Editing it is refused
    // by the API as well; the buttons go rather than fail (docs/assessments.md).
    if (!canManage || !assessment.isDraft) {
      return Row(mainAxisSize: MainAxisSize.min, children: [marks]);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marks,
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit test',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AssessmentDialog(assessment: assessment),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Delete test',
          onPressed: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete test?'),
        content: Text('This will permanently delete "${assessment.title}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(assessmentListNotifierProvider.notifier).deleteAssessment(assessment);
      messenger.showSnackBar(SnackBar(content: Text('${assessment.title} was deleted.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
