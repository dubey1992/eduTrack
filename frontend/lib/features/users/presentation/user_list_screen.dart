import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/responsive.dart';
import '../application/user_list_notifier.dart';
import '../data/models/app_user.dart';
import 'add_user_dialog.dart';

class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(userListNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add user',
            onPressed: () => showDialog(context: context, builder: (_) => const AddUserDialog()),
          ),
        ],
      ),
      body: AsyncValueView<List<AppUser>>(
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
          child: ListTile(
            title: Text(user.name),
            subtitle: Text('${user.email}\n${user.role.label}'),
            isThreeLine: true,
            trailing: _StatusToggle(user: user),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.success.withValues(alpha: 0.12) : AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: isActive ? AppTheme.success : AppTheme.danger,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
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
