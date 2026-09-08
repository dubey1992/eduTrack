import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/user_list_notifier.dart';
import '../data/models/app_user.dart';
import 'add_user_dialog.dart';

class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(userListNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Users',
          actions: [
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const AddUserDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add User'),
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<List<AppUser>>(
            value: usersState,
            onRetry: () => ref.read(userListNotifierProvider.notifier).refresh(),
            isEmpty: (users) => users.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No users yet.')),
            data: (context, users) {
              return ResponsiveBuilder(
                mobile: (context) => _UserListMobile(users: users),
                desktop: (context) => _UserListDesktop(users: users),
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
              subtitle: Text('${user.email}\n${user.role.label}'),
              isThreeLine: true,
              trailing: _StatusToggle(user: user),
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
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
                    DataCell(Text(user.role.label)),
                    DataCell(_StatusBadge(status: user.status)),
                    DataCell(_StatusToggle(user: user)),
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

    return StatusBadge(
      label: isActive ? 'Active' : 'Inactive',
      tone: isActive ? BadgeTone.success : BadgeTone.danger,
    );
  }
}

class _StatusToggle extends ConsumerWidget {
  const _StatusToggle({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = user.status == UserStatus.active;

    return TextButton(
      onPressed: () => ref.read(userListNotifierProvider.notifier).setActive(user, !isActive),
      child: Text(isActive ? 'Deactivate' : 'Activate'),
    );
  }
}
