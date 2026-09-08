import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../models/user_role.dart';
import '../routing/app_nav.dart';

/// The persistent navigation sidebar - grouped, role-filtered nav items,
/// matching the prototype's `<aside class="sidebar">` (brand header, nav
/// groups in small-caps, active-item highlight). Used both as the fixed
/// desktop sidebar and as the mobile drawer's content by [AppShell].
class SidebarNav extends ConsumerWidget {
  const SidebarNav({super.key, this.onNavigate});

  /// Called after navigating - lets the mobile drawer close itself.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authNotifierProvider).value?.role;
    final currentPath = GoRouterState.of(context).matchedLocation;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('EduTrack School', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'School Management',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            for (final group in AppNav.groups)
              if (role != null && group.items.any((item) => item.allows(role)))
                _NavGroupSection(group: group, role: role, currentPath: currentPath, onNavigate: onNavigate),
          ],
        ),
      ),
    );
  }
}

class _NavGroupSection extends StatelessWidget {
  const _NavGroupSection({
    required this.group,
    required this.role,
    required this.currentPath,
    required this.onNavigate,
  });

  final NavGroup group;
  final UserRole role;
  final String currentPath;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final visibleItems = group.items.where((item) => item.allows(role)).toList();
    if (visibleItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(
            group.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final item in visibleItems)
          _NavTile(item: item, selected: currentPath == item.path, onNavigate: onNavigate),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onNavigate});

  final NavItem item;
  final bool selected;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            context.go(item.path);
            onNavigate?.call();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: selected ? colorScheme.onPrimary : colorScheme.onSurface),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
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
