import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user_role.dart';
import '../../auth/application/auth_notifier.dart';

/// Placeholder landing screen proving the auth pipe works end to end.
/// Phase 18 replaces this with the real dashboard (KPIs, quick actions,
/// the full sidebar) from the prototype.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user == null ? 'Welcome' : 'Welcome, ${user.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (user?.role == UserRole.superAdmin || user?.role == UserRole.schoolAdmin) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => context.push('/users'),
                icon: const Icon(Icons.group_outlined),
                label: const Text('Manage Users'),
              ),
            ],
            if (user?.role == UserRole.superAdmin) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/schools'),
                icon: const Icon(Icons.apartment_outlined),
                label: const Text('Manage Schools'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
