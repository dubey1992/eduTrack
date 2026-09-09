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
import '../application/department_list_notifier.dart';
import '../data/models/department.dart';
import 'add_department_dialog.dart';
import 'edit_department_dialog.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.schoolAdmin};

class DepartmentListScreen extends ConsumerStatefulWidget {
  const DepartmentListScreen({super.key});

  @override
  ConsumerState<DepartmentListScreen> createState() => _DepartmentListScreenState();
}

class _DepartmentListScreenState extends ConsumerState<DepartmentListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final departmentsState = ref.watch(departmentPageNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Departments',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddDepartmentDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Department'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(departmentPageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<Department>>(
            value: departmentsState,
            onRetry: () => ref.read(departmentPageNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No departments set up yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) =>
                          _DepartmentGrid(departments: page.items, canManage: canManage, crossAxisCount: 1),
                      desktop: (context) =>
                          _DepartmentGrid(departments: page.items, canManage: canManage, crossAxisCount: 3),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(departmentPageNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(departmentPageNotifierProvider.notifier).setPerPage(p),
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

class _DepartmentGrid extends StatelessWidget {
  const _DepartmentGrid({required this.departments, required this.canManage, required this.crossAxisCount});

  final List<Department> departments;
  final bool canManage;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: 110,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: departments.length,
      itemBuilder: (context, index) {
        return _DepartmentCard(department: departments[index], canManage: canManage);
      },
    );
  }
}

class _DepartmentCard extends ConsumerWidget {
  const _DepartmentCard({required this.department, required this.canManage});

  final Department department;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    department.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canManage) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => EditDepartmentDialog(department: department),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                ],
              ],
            ),
            const Spacer(),
            Text(
              department.hodName != null ? 'HOD: ${department.hodName}' : 'No HOD assigned',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete department?'),
        content: Text('This will permanently delete "${department.name}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(departmentPageNotifierProvider.notifier).deleteDepartment(department);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${department.name} was deleted.')));
      }
    } catch (error) {
      if (context.mounted) {
        final failure = error is Failure ? error : Failure.unknown(error.toString());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}
