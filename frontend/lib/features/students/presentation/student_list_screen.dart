import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../imports/presentation/bulk_import_button.dart';
import '../application/student_list_notifier.dart';
import '../data/models/student.dart';
import 'add_student_dialog.dart';
import 'edit_student_dialog.dart';
import 'student_history_dialog.dart';
import 'student_performance_dialog.dart';
import 'widgets/student_class_panel.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  final _searchController = TextEditingController();
  int? _schoolFilter;
  StudentStatus? _statusFilter;
  StudentSectionChoice? _section;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Room for the class list beside the table, the table, and its actions.
  static const double _panelMinWidth = 1500;

  Widget _withPanel(AsyncValue<PagedList<Student>> studentsState, bool canManage) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 220,
          child: StudentClassPanel(schoolId: _schoolFilter, selected: _section?.id, onSelected: _choose),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _search(width: 280),
              _sectionBar(canManage),
              const SizedBox(height: 12),
              Expanded(child: _list(studentsState, canManage)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _withPicker(AsyncValue<PagedList<Student>> studentsState, bool canManage, double width) {
    final narrow = width < Breakpoints.desktop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 20, right: narrow ? 20 : 0),
              child: SizedBox(
                width: narrow ? width - 40 : 280,
                child: StudentClassPicker(schoolId: _schoolFilter, selected: _section?.id, onSelected: _choose),
              ),
            ),
            if (narrow) _search(width: width - 40) else SizedBox(width: 280, child: _search(width: 280, padded: false)),
          ],
        ),
        _sectionBar(canManage),
        const SizedBox(height: 12),
        Expanded(child: _list(studentsState, canManage)),
      ],
    );
  }

  /// Pick a section to see its students by roll number; null is everybody.
  void _choose(StudentSectionChoice? section) {
    setState(() => _section = section);
    ref.read(studentListNotifierProvider.notifier).setSection(section?.id);
  }

  Widget _search({required double width, bool padded = true}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padded ? 20 : 0),
      child: SizedBox(
        width: width,
        child: DebouncedSearchField(
          controller: _searchController,
          label: 'Search by name / admission ID',
          onSearch: (value) => ref.read(studentListNotifierProvider.notifier).setSearch(value),
        ),
      ),
    );
  }

  /// Which section is showing, and Renumber A-Z for it.
  Widget _sectionBar(bool canManage) {
    final section = _section;
    if (section == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('${section.label} · in roll number order', style: Theme.of(context).textTheme.titleSmall),
          ),
          if (canManage && section.students > 0)
            TextButton.icon(
              key: const Key('renumber-section'),
              onPressed: () => _renumber(section),
              icon: const Icon(Icons.sort_by_alpha, size: 18),
              label: const Text('Renumber A-Z'),
            ),
        ],
      ),
    );
  }

  Future<void> _renumber(StudentSectionChoice section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Renumber ${section.label}?'),
        content: Text(
          'The ${section.students} active students of ${section.label} get roll numbers 1 to '
          '${section.students} in alphabetical order. Their current roll numbers are replaced.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Renumber')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final numbered = await ref.read(studentListNotifierProvider.notifier).renumber(section.id);
      messenger.showSnackBar(SnackBar(content: Text('Renumbered $numbered students of ${section.label}.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Widget _list(AsyncValue<PagedList<Student>> studentsState, bool canManage) {
    return AsyncValueView<PagedList<Student>>(
      value: studentsState,
      onRetry: () => ref.read(studentListNotifierProvider.notifier).refresh(),
      isEmpty: (page) => page.items.isEmpty,
      // Two very different emptinesses, and telling somebody their
      // school has no students when they have simply mistyped a name is
      // the sort of thing that gets reported as data loss.
      emptyBuilder: (context) => Center(
        child: Text(
          _searchController.text.trim().isNotEmpty
              ? 'No students match this search.'
              : _section != null
              ? 'No students in ${_section!.label} yet.'
              : 'No students admitted yet.',
        ),
      ),
      data: (context, page) {
        return Column(
          children: [
            Expanded(
              child: ResponsiveBuilder(
                mobile: (context) => _StudentListMobile(students: page.items, canManage: canManage),
                desktop: (context) => _StudentListDesktop(students: page.items, canManage: canManage),
              ),
            ),
            PaginationControls(
              currentPage: page.currentPage,
              lastPage: page.lastPage,
              total: page.total,
              perPage: page.perPage,
              onPageChanged: (p) => ref.read(studentListNotifierProvider.notifier).goToPage(p),
              onPerPageChanged: (p) => ref.read(studentListNotifierProvider.notifier).setPerPage(p),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentsState = ref.watch(studentListNotifierProvider);
    final canManage = ref.watch(authNotifierProvider).value?.canManage(AppModules.students) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Student Management',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddStudentDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Student'),
              ),
            if (canManage)
              BulkImportButton(
                type: 'students',
                title: 'Students',
                schoolId: _schoolFilter,
                onImported: () {
                  ref.invalidate(studentClassesProvider);
                  ref.read(studentListNotifierProvider.notifier).refresh();
                },
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() {
                  _schoolFilter = schoolId;
                  _section = null;
                });
                ref.read(studentListNotifierProvider.notifier)
                  ..setSection(null)
                  ..setSchoolFilter(schoolId);
              },
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<StudentStatus?>(
                key: const Key('student-status-filter'),
                initialValue: _statusFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem<StudentStatus?>(value: null, child: Text('Any status')),
                  for (final status in StudentStatus.values)
                    DropdownMenuItem<StudentStatus?>(value: status, child: Text(status.label)),
                ],
                onChanged: (status) {
                  setState(() => _statusFilter = status);
                  ref.read(studentListNotifierProvider.notifier).setStatusFilter(status);
                },
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            // The class list sits beside the table only where the table still
            // fits next to it; elsewhere it is a dropdown above the list.
            builder: (context, constraints) => constraints.maxWidth >= _panelMinWidth
                ? _withPanel(studentsState, canManage)
                : _withPicker(studentsState, canManage, constraints.maxWidth),
          ),
        ),
      ],
    );
  }
}

class _StudentListMobile extends StatelessWidget {
  const _StudentListMobile({required this.students, required this.canManage});

  final List<Student> students;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final student = students[index];
        return Card(
          child: ListTile(
            title: Text('${student.rollNumber == null ? '' : 'Roll ${student.rollNumber} · '}${student.name}'),
            subtitle: Text(
              '${student.admissionNumber} · ${student.classSectionName ?? '-'} · Guardian: ${student.guardianName} · '
              '${_transportLabel(student)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadgeFor(student: student),
                IconButton(
                  icon: const Icon(Icons.history, size: 20),
                  tooltip: 'Class history',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => StudentHistoryDialog(student: student),
                  ),
                ),
              ],
            ),
            onTap: canManage
                ? () => showDialog(
                    context: context,
                    builder: (_) => EditStudentDialog(student: student),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _StudentListDesktop extends StatelessWidget {
  const _StudentListDesktop({required this.students, required this.canManage});

  final List<Student> students;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            // The admission number sits under the name, so the class list
            // beside the table leaves room for the actions (docs/onboarding.md).
            dataRowMaxHeight: 60,
            columns: const [
              DataColumn(label: Text('Roll')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Class')),
              DataColumn(label: Text('Parent')),
              DataColumn(label: Text('Transport')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final student in students)
                DataRow(
                  cells: [
                    DataCell(Text(student.rollNumber ?? '-')),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.name),
                          Text(student.admissionNumber, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    DataCell(Text(student.classSectionName ?? '-')),
                    DataCell(Text(student.guardianName)),
                    DataCell(Text(_transportLabel(student))),
                    DataCell(_StatusBadgeFor(student: student)),
                    DataCell(_StudentActions(student: student, canManage: canManage)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Bus 04 - Green Park (Lake View)" or "No Transport" - the prototype's
/// Transport column.
String _transportLabel(Student student) {
  final transport = student.transport;
  return transport == null ? 'No Transport' : '${transport.routeLabel} (${transport.stopName})';
}

class _StatusBadgeFor extends StatelessWidget {
  const _StatusBadgeFor({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    // Graduated is neither active nor a failure: a child who finished reads
    // as finished, not as a red "Inactive" (docs/promotion.md).
    const tones = {
      StudentStatus.active: BadgeTone.success,
      StudentStatus.inactive: BadgeTone.danger,
      StudentStatus.graduated: BadgeTone.info,
    };

    return StatusBadge(label: student.status.label, tone: tones[student.status] ?? BadgeTone.danger);
  }
}

class _StudentActions extends ConsumerWidget {
  const _StudentActions({required this.student, required this.canManage});

  final Student student;

  /// False for the read-only roles. They still reach the class history,
  /// because a teacher asking what a child did last year should not need an
  /// administrator (docs/promotion.md).
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = student.status == StudentStatus.active;
    // The Performance dialog belongs to the assessments module: a school
    // with class tests switched off has no performance, and the API says so
    // too (docs/assessments.md).
    final seesPerformance = ref.watch(authNotifierProvider).value?.moduleOn(AppModules.assessments) ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.history, size: 20),
          tooltip: 'Class history',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => StudentHistoryDialog(student: student),
          ),
        ),
        // Open to every role that may see the student, like the history:
        // "how is this child doing" is the question a teacher asks most.
        if (seesPerformance)
          IconButton(
            icon: const Icon(Icons.insights_outlined, size: 20),
            tooltip: 'Performance',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => StudentPerformanceDialog(student: student),
            ),
          ),
        if (canManage)
          TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditStudentDialog(student: student),
            ),
            child: const Text('View'),
          ),
        if (canManage)
          TextButton(
            onPressed: () async {
              try {
                await ref.read(studentListNotifierProvider.notifier).setActive(student, !isActive);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${student.name} is now ${isActive ? 'inactive' : 'active'}.')),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  final failure = error is Failure ? error : Failure.unknown(error.toString());
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
                }
              }
            },
            child: Text(isActive ? 'Deactivate' : 'Activate'),
          ),
      ],
    );
  }
}
