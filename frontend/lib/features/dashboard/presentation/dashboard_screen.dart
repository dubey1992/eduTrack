import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/responsive.dart';
import '../../auth/application/auth_notifier.dart';

/// Landing screen after login. Phase 18 replaces this with the full
/// dashboard (KPIs, activity feed) from the prototype; for now it welcomes
/// the user and offers quick links into whatever this phase has built.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    final role = user?.role;

    final quickActions = [
      if (role == UserRole.superAdmin)
        _QuickAction(
          icon: Icons.apartment_outlined,
          title: 'Manage Schools',
          subtitle: 'Onboard and configure schools',
          onTap: () => context.go('/schools'),
        ),
      if (role == UserRole.superAdmin)
        _QuickAction(
          icon: Icons.payments_outlined,
          title: 'Record Payment',
          subtitle: 'Log a payment received from a school',
          onTap: () => context.go('/payments'),
        ),
      if (role == UserRole.superAdmin || role == UserRole.schoolAdmin)
        _QuickAction(
          icon: Icons.group_outlined,
          title: 'Manage Users',
          subtitle: 'Accounts, roles and access',
          onTap: () => context.go('/users'),
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user == null ? 'Welcome' : 'Welcome, ${user.name}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (quickActions.isNotEmpty) ...[
            Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ResponsiveBuilder(
              mobile: (context) => Column(
                children: [
                  for (final action in quickActions) Padding(padding: const EdgeInsets.only(bottom: 10), child: action),
                ],
              ),
              desktop: (context) => Wrap(spacing: 12, runSpacing: 12, children: quickActions),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A fixed height (rather than letting the Card size to its own content)
    // keeps every card in the row the same height regardless of subtitle
    // length - these sit in a Wrap, which (unlike a Row) never stretches
    // siblings to match each other, so a two-line subtitle would otherwise
    // make just that one card taller than the rest. maxLines/ellipsis is a
    // defensive cap so a longer subtitle in the future still fits.
    return SizedBox(
      width: 260,
      height: 112,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
