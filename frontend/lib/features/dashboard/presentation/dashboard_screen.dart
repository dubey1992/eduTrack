import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';

/// Placeholder landing screen proving the auth pipe works end to end.
/// Phase 4+ replaces this with the real dashboard (KPIs, quick actions)
/// from the prototype.
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
        child: Text(
          user == null ? 'Welcome' : 'Welcome, ${user.name}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
