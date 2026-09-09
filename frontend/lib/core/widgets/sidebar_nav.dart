import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../models/user_role.dart';
import '../routing/app_nav.dart';

/// The prototype's sidebar is a fixed dark surface (`--sidebar:#111827` etc.
/// in its default theme) independent of the rest of the app's light/dark
/// mode - not something derived from [Theme.of(context).colorScheme], which
/// would otherwise turn it white in light mode. Matches
/// docs/prototype/school_management_prototype_v4_themes.html's `:root`
/// tokens.
class _SidebarColors {
  const _SidebarColors._();

  static const background = Color(0xFF111827);
  static const text = Color(0xFFCBD5E1);
  static const subtext = Color(0xFF94A3B8);
  static const groupLabel = Color(0xFF64748B);
  static const activeBackground = Color(0xFF1F2937);
  static const activeText = Colors.white;
}

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

    return Container(
      color: _SidebarColors.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'School365ai',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _SidebarColors.activeText),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('School Management', style: TextStyle(fontSize: 13, color: _SidebarColors.subtext)),
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
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _SidebarColors.groupLabel,
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
    final color = selected ? _SidebarColors.activeText : _SidebarColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? _SidebarColors.activeBackground : Colors.transparent,
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
                Icon(item.icon, size: 19, color: color),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
