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
import '../../auth/application/auth_notifier.dart';
import '../../imports/presentation/bulk_import_button.dart';
import '../application/subject_list_notifier.dart';
import '../data/models/subject.dart';
import 'add_subject_dialog.dart';
import 'edit_subject_dialog.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin};

class SubjectListScreen extends ConsumerStatefulWidget {
  const SubjectListScreen({super.key});

  @override
  ConsumerState<SubjectListScreen> createState() => _SubjectListScreenState();
}

class _SubjectListScreenState extends ConsumerState<SubjectListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final subjectsState = ref.watch(subjectListNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Subjects',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddSubjectDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Subject'),
              ),
            if (canManage)
              BulkImportButton(
                type: 'subjects',
                title: 'Subjects',
                schoolId: _schoolFilter,
                onImported: () => ref.read(subjectListNotifierProvider.notifier).refresh(),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(subjectListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<Subject>>(
            value: subjectsState,
            onRetry: () => ref.read(subjectListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No subjects set up yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _SubjectListMobile(subjects: page.items, canManage: canManage),
                      desktop: (context) => _SubjectListDesktop(subjects: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(subjectListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(subjectListNotifierProvider.notifier).setPerPage(p),
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

class _SubjectListMobile extends StatelessWidget {
  const _SubjectListMobile({required this.subjects, required this.canManage});

  final List<Subject> subjects;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: subjects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final subject = subjects[index];
        return Card(
          child: ListTile(
            title: Text('${subject.code} · ${subject.name}'),
            subtitle: Text(
              '${subject.departmentName ?? '-'} · Grades ${subject.minClassLevel}-${subject.maxClassLevel}'
              '${subject.leadTeacherName != null ? '\nLead: ${subject.leadTeacherName}' : ''}',
            ),
            isThreeLine: subject.leadTeacherName != null,
            trailing: canManage ? _SubjectActions(subject: subject) : null,
          ),
        );
      },
    );
  }
}

class _SubjectListDesktop extends StatelessWidget {
  const _SubjectListDesktop({required this.subjects, required this.canManage});

  final List<Subject> subjects;
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
              DataColumn(label: Text('Code')),
              DataColumn(label: Text('Subject')),
              DataColumn(label: Text('Department')),
              DataColumn(label: Text('Classes')),
              DataColumn(label: Text('Lead Teacher')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final subject in subjects)
                DataRow(
                  cells: [
                    DataCell(Text(subject.code)),
                    DataCell(Text(subject.name)),
                    DataCell(Text(subject.departmentName ?? '-')),
                    DataCell(Text('${subject.minClassLevel}-${subject.maxClassLevel}')),
                    DataCell(Text(subject.leadTeacherName ?? '-')),
                    DataCell(canManage ? _SubjectActions(subject: subject) : const SizedBox.shrink()),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectActions extends ConsumerWidget {
  const _SubjectActions({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditSubjectDialog(subject: subject),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete subject?'),
        content: Text('This will permanently delete "${subject.name}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(subjectListNotifierProvider.notifier).deleteSubject(subject);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${subject.name} was deleted.')));
      }
    } catch (error) {
      if (context.mounted) {
        final failure = error is Failure ? error : Failure.unknown(error.toString());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}
