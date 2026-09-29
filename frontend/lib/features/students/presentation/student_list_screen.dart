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

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  final _searchController = TextEditingController();
  int? _schoolFilter;
  StudentStatus? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                onImported: () => ref.read(studentListNotifierProvider.notifier).refresh(),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(studentListNotifierProvider.notifier).setSchoolFilter(schoolId);
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: 280,
            child: DebouncedSearchField(
              controller: _searchController,
              label: 'Search by name / admission ID',
              onSearch: (value) => ref.read(studentListNotifierProvider.notifier).setSearch(value),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncValueView<PagedList<Student>>(
            value: studentsState,
            onRetry: () => ref.read(studentListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            // Two very different emptinesses, and telling somebody their
            // school has no students when they have simply mistyped a name is
            // the sort of thing that gets reported as data loss.
            emptyBuilder: (context) => Center(
              child: Text(
                _searchController.text.trim().isEmpty ? 'No students admitted yet.' : 'No students match this search.',
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
            title: Text('${student.admissionNumber} · ${student.name}'),
            subtitle: Text(
              '${student.classSectionName ?? '-'} · Guardian: ${student.guardianName} · ${_transportLabel(student)}',
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
            columns: const [
              DataColumn(label: Text('ID')),
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
                    DataCell(Text(student.admissionNumber)),
                    DataCell(Text(student.name)),
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
