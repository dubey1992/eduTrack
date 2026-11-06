import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/data/models/authenticated_user.dart';
import '../routing/app_nav.dart';

/// The prototype's sidebar colours (`--sidebar:#111827` and friends in its
/// default theme, docs/prototype/school_management_prototype_v4_themes.html):
/// a fixed dark surface whatever the app's light/dark mode, so they are not
/// taken from [Theme.of(context).colorScheme].
class _SidebarColors {
  const _SidebarColors._();

  static const background = Color(0xFF111827);
  static const text = Color(0xFFCBD5E1);
  static const subtext = Color(0xFF94A3B8);
  static const groupLabel = Color(0xFF64748B);
  static const activeBackground = Color(0xFF1F2937);
  static const activeText = Colors.white;
  // The prototype's --primary: marks the area that is open.
  static const primary = Color(0xFF2563EB);
}

/// Whether the list of an area's screens is showing beside the icon strip.
/// Folded away, the page gets the width (docs/navigation-tabs.md).
final navPanelOpenProvider = NotifierProvider<NavPanelOpen, bool>(NavPanelOpen.new);

class NavPanelOpen extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

/// The app's menu (docs/navigation-tabs.md, S2 - chosen 2026-11-06): a strip
/// of area icons, and beside it the open area's screens.
///
/// On a computer, an area's icon opens its first screen, and the list can be
/// folded away. In the phone's drawer, an area's icon only shows its list,
/// so the person picks the screen they came for.
class SidebarNav extends ConsumerStatefulWidget {
  const SidebarNav({super.key, this.onNavigate, this.inDrawer = false});

  /// Called after navigating - lets the mobile drawer close itself.
  final VoidCallback? onNavigate;

  /// Shown in the phone's drawer rather than beside the page.
  final bool inDrawer;

  @override
  ConsumerState<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends ConsumerState<SidebarNav> {
  /// The area picked in the drawer, before a screen in it is chosen.
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).value;
    if (user == null) return const ColoredBox(color: _SidebarColors.background);

    final currentPath = GoRouterState.of(context).matchedLocation;
    final groups = AppNav.groupsFor(user);
    if (groups.isEmpty) return const ColoredBox(color: _SidebarColors.background);

    final current = AppNav.groupOf(currentPath);
    final shown =
        groups.where((group) => group.label == _picked).firstOrNull ??
        groups.where((group) => group.label == current?.label).firstOrNull ??
        groups.first;
    final panelOpen = widget.inDrawer || ref.watch(navPanelOpenProvider);

    return ColoredBox(
      color: _SidebarColors.background,
      child: SafeArea(
        child: Row(
          mainAxisSize: widget.inDrawer ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rail(
              groups: groups,
              selected: shown,
              showToggle: !widget.inDrawer,
              panelOpen: panelOpen,
              onSelect: (group) => _openArea(group, user, shown),
            ),
            if (panelOpen) ...[
              const VerticalDivider(width: 1, thickness: 1, color: _SidebarColors.activeBackground),
              if (widget.inDrawer)
                Expanded(
                  child: _Panel(group: shown, user: user, currentPath: currentPath, onNavigate: _navigated),
                )
              else
                SizedBox(
                  width: 240,
                  child: _Panel(group: shown, user: user, currentPath: currentPath, onNavigate: _navigated),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _openArea(NavGroup group, AuthenticatedUser user, NavGroup shown) {
    if (widget.inDrawer) {
      setState(() => _picked = group.label);
      return;
    }

    if (!ref.read(navPanelOpenProvider)) ref.read(navPanelOpenProvider.notifier).toggle();
    if (group.label == shown.label) return;

    context.go(group.itemsFor(user).first.path);
  }

  void _navigated() {
    _picked = null;
    widget.onNavigate?.call();
  }
}

/// The strip of area icons, each named underneath.
class _Rail extends ConsumerWidget {
  const _Rail({
    required this.groups,
    required this.selected,
    required this.showToggle,
    required this.panelOpen,
    required this.onSelect,
  });

  final List<NavGroup> groups;
  final NavGroup selected;
  final bool showToggle;
  final bool panelOpen;
  final ValueChanged<NavGroup> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          const SizedBox(height: 14),
          // The logo goes home, as a logo does (asked for 2026-11-06).
          Tooltip(
            message: 'Go to the Dashboard',
            child: InkWell(
              key: const Key('nav-logo'),
              borderRadius: BorderRadius.circular(11),
              onTap: () => context.go('/dashboard'),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _SidebarColors.primary, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.school, color: Colors.white, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // A dozen icons at most: all built at once, scrolling only on a
          // short window.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final group in groups)
                    _RailButton(group: group, selected: group.label == selected.label, onTap: () => onSelect(group)),
                ],
              ),
            ),
          ),
          if (showToggle)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IconButton(
                key: const Key('nav-panel-toggle'),
                tooltip: panelOpen ? 'Hide the list of screens' : 'Show the list of screens',
                color: _SidebarColors.subtext,
                icon: Icon(panelOpen ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right),
                onPressed: () => ref.read(navPanelOpenProvider.notifier).toggle(),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.group, required this.selected, required this.onTap});

  final NavGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: group.label,
        excludeSemantics: true,
        child: InkWell(
          key: Key('nav-area-${group.label}'),
          borderRadius: BorderRadius.circular(10),
          hoverColor: _SidebarColors.activeBackground,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected ? _SidebarColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(group.icon, size: 20, color: selected ? _SidebarColors.activeText : _SidebarColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  group.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? _SidebarColors.activeText : _SidebarColors.subtext,
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

/// The open area's screens, styled as the prototype's nav list.
class _Panel extends StatelessWidget {
  const _Panel({required this.group, required this.user, required this.currentPath, required this.onNavigate});

  final NavGroup group;
  final AuthenticatedUser user;
  final String currentPath;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('nav-panel'),
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
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('School Management', style: TextStyle(fontSize: 13, color: _SidebarColors.subtext)),
        ),
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
        for (final item in group.itemsFor(user))
          _NavTile(item: item, selected: currentPath == item.path, onNavigate: onNavigate),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onNavigate});

  final NavItem item;
  final bool selected;
  final VoidCallback onNavigate;

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
          hoverColor: _SidebarColors.activeBackground,
          onTap: () {
            context.go(item.path);
            onNavigate();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: color),
                const SizedBox(width: 10),
                // Flexible with an ellipsis: the list is a fixed width and a
                // long label - or a larger system font - would otherwise run
                // past its edge rather than trimming.
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
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
