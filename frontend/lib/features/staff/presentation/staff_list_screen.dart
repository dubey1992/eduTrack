import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../imports/presentation/bulk_import_button.dart';
import '../../departments/application/department_list_notifier.dart';
import '../../users/data/models/app_user.dart';
import '../application/staff_list_notifier.dart';
import '../data/models/staff_profile.dart';
import 'add_staff_dialog.dart';
import 'edit_staff_profile_dialog.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin};
const _staffRoles = [UserRole.teacher, UserRole.hod, UserRole.staff, UserRole.transportManager];

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final _searchController = TextEditingController();
  int? _departmentFilter;
  UserRole? _roleFilter;
  int? _schoolFilter;

  /// Whether anything is narrowing the list, so an empty page can say which
  /// kind of empty it is. "No teachers or staff added yet" is alarming to read
  /// when the truth is that a name was mistyped.
  bool get _isFiltered => _searchController.text.trim().isNotEmpty || _departmentFilter != null || _roleFilter != null;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffState = ref.watch(staffListNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Teachers & Staff',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddStaffDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Employee'),
              ),
            if (canManage)
              BulkImportButton(
                type: 'staff',
                title: 'Teachers and Staff',
                schoolId: _schoolFilter,
                onImported: () => ref.read(staffListNotifierProvider.notifier).refresh(),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(staffListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        // Outside the AsyncValueView below, and deliberately: a search puts
        // the list into its loading state, and anything drawn inside that
        // view is torn down and rebuilt when it does. With the search box in
        // there it lost the keyboard focus the moment the results came back,
        // mid-word - and an empty result took the box away altogether,
        // leaving no way to clear the search that caused it.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _Filters(
            searchController: _searchController,
            departmentFilter: _departmentFilter,
            roleFilter: _roleFilter,
            onSearchChanged: (value) {
              ref.read(staffListNotifierProvider.notifier).setSearch(value);
            },
            onDepartmentChanged: (value) {
              setState(() => _departmentFilter = value);
              ref.read(staffListNotifierProvider.notifier).setDepartmentFilter(value);
            },
            onRoleChanged: (value) {
              setState(() => _roleFilter = value);
              ref.read(staffListNotifierProvider.notifier).setRoleFilter(value);
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncValueView<PagedList<StaffProfile>>(
            value: staffState,
            onRetry: () => ref.read(staffListNotifierProvider.notifier).refresh(),
            data: (context, page) {
              final staff = page.items;

              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _StatRow(staff: staff),
                          ),
                          const SizedBox(height: 12),
                          if (staff.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(
                                  _isFiltered ? 'No employees match these filters.' : 'No teachers or staff added yet.',
                                ),
                              ),
                            )
                          else
                            ResponsiveBuilder(
                              mobile: (context) => _StaffListMobile(staff: staff, canManage: canManage),
                              desktop: (context) => _StaffListDesktop(staff: staff, canManage: canManage),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(staffListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(staffListNotifierProvider.notifier).setPerPage(p),
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.staff});

  final List<StaffProfile> staff;

  @override
  Widget build(BuildContext context) {
    final teachers = staff.where((m) => m.role == UserRole.teacher).length;
    final nonTeaching = staff.where((m) => m.role == UserRole.staff || m.role == UserRole.transportManager).length;
    final hods = staff.where((m) => m.role == UserRole.hod).length;
    final active = staff.where((m) => m.status == UserStatus.active).length;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        KpiCard(label: 'Teachers', value: '$teachers'),
        KpiCard(label: 'Non-Teaching Staff', value: '$nonTeaching'),
        KpiCard(label: 'HODs', value: '$hods'),
        KpiCard(label: 'Active', value: '$active'),
      ],
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({
    required this.searchController,
    required this.departmentFilter,
    required this.roleFilter,
    required this.onSearchChanged,
    required this.onDepartmentChanged,
    required this.onRoleChanged,
  });

  final TextEditingController searchController;
  final int? departmentFilter;
  final UserRole? roleFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onDepartmentChanged;
  final ValueChanged<UserRole?> onRoleChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departmentsState = ref.watch(departmentListNotifierProvider);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 220,
          child: DebouncedSearchField(
            controller: searchController,
            label: 'Search employee',
            onSearch: onSearchChanged,
          ),
        ),
        SizedBox(
          width: 200,
          child: AsyncValueView(
            value: departmentsState,
            data: (context, departments) {
              return DropdownButtonFormField<int?>(
                initialValue: departmentFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Departments')),
                  for (final department in departments)
                    DropdownMenuItem(value: department.id, child: Text(department.name)),
                ],
                onChanged: onDepartmentChanged,
              );
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<UserRole?>(
            initialValue: roleFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Role', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Roles')),
              for (final role in _staffRoles) DropdownMenuItem(value: role, child: Text(role.label)),
            ],
            onChanged: onRoleChanged,
          ),
        ),
      ],
    );
  }
}

class _StaffListMobile extends StatelessWidget {
  const _StaffListMobile({required this.staff, required this.canManage});

  final List<StaffProfile> staff;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: staff.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final member = staff[index];
        return Card(
          child: ListTile(
            title: Text('${member.employeeId} · ${member.name}'),
            subtitle: Text(
              '${member.departmentName ?? '-'} · ${_roleBadgeLabel(member)}'
              '${member.classTeacherOf.isNotEmpty ? '\nClasses: ${member.classTeacherOf.join(', ')}' : ''}',
            ),
            isThreeLine: member.classTeacherOf.isNotEmpty,
            trailing: _StatusBadgeFor(member: member),
            onTap: canManage
                ? () => showDialog(
                    context: context,
                    builder: (_) => EditStaffProfileDialog(profile: member),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _StaffListDesktop extends StatelessWidget {
  const _StaffListDesktop({required this.staff, required this.canManage});

  final List<StaffProfile> staff;
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
              DataColumn(label: Text('Department')),
              DataColumn(label: Text('Assigned Classes')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final member in staff)
                DataRow(
                  cells: [
                    DataCell(Text(member.employeeId)),
                    DataCell(Text(member.name)),
                    DataCell(Text(member.departmentName ?? '-')),
                    DataCell(Text(member.classTeacherOf.isEmpty ? '-' : member.classTeacherOf.join(', '))),
                    DataCell(StatusBadge(label: _roleBadgeLabel(member), tone: BadgeTone.info)),
                    DataCell(_StatusBadgeFor(member: member)),
                    DataCell(canManage ? _StaffActions(member: member) : const SizedBox.shrink()),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _roleBadgeLabel(StaffProfile member) {
  if (member.role == UserRole.teacher && member.classTeacherOf.isNotEmpty) {
    return 'Class Teacher ${member.classTeacherOf.first}';
  }
  return member.designation ?? member.role.label;
}

class _StatusBadgeFor extends StatelessWidget {
  const _StatusBadgeFor({required this.member});

  final StaffProfile member;

  @override
  Widget build(BuildContext context) {
    final isActive = member.status == UserStatus.active;
    return StatusBadge(label: isActive ? 'Active' : 'Inactive', tone: isActive ? BadgeTone.success : BadgeTone.danger);
  }
}

class _StaffActions extends ConsumerWidget {
  const _StaffActions({required this.member});

  final StaffProfile member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = member.status == UserStatus.active;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditStaffProfileDialog(profile: member),
          ),
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await ref.read(staffListNotifierProvider.notifier).setActive(member, !isActive);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('${member.name} is now ${isActive ? 'inactive' : 'active'}.')));
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
