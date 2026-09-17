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
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/user_list_notifier.dart';
import '../data/models/app_user.dart';
import 'add_user_dialog.dart';
import 'edit_user_dialog.dart';

class UserListScreen extends ConsumerStatefulWidget {
  const UserListScreen({super.key});

  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends ConsumerState<UserListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(userListNotifierProvider);
    final actor = ref.watch(authNotifierProvider).value;
    final isSuperAdmin = actor?.role == UserRole.superAdmin;
    // A School or Group Admin who isn't themselves a Sub Admin can create
    // one; a Sub Admin can't create any admin account at all (see the
    // backend's UserPolicy::create()) - no point showing a button that
    // would 403.
    final canCreateSubAdmin = actor?.role.administersSchool == true && actor?.isSubAdmin == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Admin Users',
          actions: [
            if (isSuperAdmin || canCreateSubAdmin)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddUserDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: Text(isSuperAdmin ? 'Add School Admin' : 'Add Sub Admin'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(userListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<AppUser>>(
            value: usersState,
            onRetry: () => ref.read(userListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No users yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _UserListMobile(users: page.items),
                      desktop: (context) => _UserListDesktop(users: page.items),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(userListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(userListNotifierProvider.notifier).setPerPage(p),
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

class _UserListMobile extends StatelessWidget {
  const _UserListMobile({required this.users});

  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(user.name, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  _StatusBadge(status: user.status),
                ],
              ),
              subtitle: Text('${user.email}\n${user.displayRoleLabel}'),
              isThreeLine: true,
              trailing: _UserActions(user: user),
            ),
          ),
        );
      },
    );
  }
}

class _UserListDesktop extends StatelessWidget {
  const _UserListDesktop({required this.users});

  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Mobile')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final user in users)
                DataRow(
                  cells: [
                    DataCell(Text(user.name)),
                    DataCell(Text(user.email)),
                    DataCell(Text(user.mobile ?? '-')),
                    DataCell(Text(user.displayRoleLabel)),
                    DataCell(_StatusBadge(status: user.status)),
                    DataCell(_UserActions(user: user)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final UserStatus status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == UserStatus.active;

    return StatusBadge(label: isActive ? 'Active' : 'Inactive', tone: isActive ? BadgeTone.success : BadgeTone.danger);
  }
}

class _UserActions extends ConsumerWidget {
  const _UserActions({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = user.status == UserStatus.active;
    final actor = ref.watch(authNotifierProvider).value;
    final isSuperAdmin = actor?.role == UserRole.superAdmin;

    // For a non-admin account (Teacher/Staff/HOD/etc.) any School Admin
    // manages it freely - only an admin-tier row (School Admin or Sub
    // Admin) needs the extra check below. A SUPER_ADMIN always manages
    // everyone. Otherwise: the head (a School Admin who isn't themselves a
    // Sub Admin) manages the Sub Admins in their own school, but never
    // another head, and a Sub Admin manages no admin-tier account at all
    // (see the backend's UserPolicy::manages()). No point showing
    // Edit/Deactivate that would always 403.
    final canManage =
        isSuperAdmin ||
        // Admin-tier is a School Admin *or* a Group Admin: a branch's admin
        // must not be offered Edit on the group's.
        !user.role.administersSchool ||
        (actor?.role.administersSchool == true && actor?.isSubAdmin == false && user.isSubAdmin);
    if (!canManage) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditUserDialog(user: user),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              await ref.read(userListNotifierProvider.notifier).setActive(user, !isActive);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('${user.name} was ${isActive ? 'deactivated' : 'activated'}.')));
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
