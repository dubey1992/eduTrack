import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/student_list_notifier.dart';
import '../data/models/student.dart';
import 'add_student_dialog.dart';
import 'edit_student_dialog.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.schoolAdmin};

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  final _searchController = TextEditingController();
  int? _schoolFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Student> _applyFilter(List<Student> students) {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isEmpty) return students;
    return students
        .where(
          (student) =>
              student.name.toLowerCase().contains(search) || student.admissionNumber.toLowerCase().contains(search),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final studentsState = ref.watch(studentListNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

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
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(studentListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name / admission ID',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncValueView<PagedList<Student>>(
            value: studentsState,
            onRetry: () => ref.read(studentListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No students admitted yet.')),
            data: (context, page) {
              final filtered = _applyFilter(page.items);

              return Column(
                children: [
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No students match this search.'))
                        : ResponsiveBuilder(
                            mobile: (context) => _StudentListMobile(students: filtered, canManage: canManage),
                            desktop: (context) => _StudentListDesktop(students: filtered, canManage: canManage),
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
            subtitle: Text('${student.classSectionName ?? '-'} · Guardian: ${student.guardianName}'),
            trailing: _StatusBadgeFor(student: student),
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Class')),
              DataColumn(label: Text('Parent')),
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
                    DataCell(_StatusBadgeFor(student: student)),
                    DataCell(canManage ? _StudentActions(student: student) : const SizedBox.shrink()),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadgeFor extends StatelessWidget {
  const _StatusBadgeFor({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    final isActive = student.status == StudentStatus.active;
    return StatusBadge(label: isActive ? 'Active' : 'Inactive', tone: isActive ? BadgeTone.success : BadgeTone.danger);
  }
}

class _StudentActions extends ConsumerWidget {
  const _StudentActions({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = student.status == StudentStatus.active;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditStudentDialog(student: student),
          ),
          child: const Text('View'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await ref.read(studentListNotifierProvider.notifier).setActive(student, !isActive);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('${student.name} is now ${isActive ? 'inactive' : 'active'}.')));
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
