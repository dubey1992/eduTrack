import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/data/models/authenticated_user.dart';
import '../../features/school_logo/presentation/school_logo_image.dart';
import '../routing/app_nav.dart';
import '../storage/key_value_store.dart';
import '../theme/brand_tokens.dart';
import 'school365_mark.dart';

/// The sidebar's colours (Warm Editorial, 2026-11-14): a plum surface
/// whatever the app's light/dark mode, as in the redesign prototype, so they
/// are not taken from [Theme.of(context).colorScheme]. What is open is
/// white with plum text; every text colour reads at 4.5:1 on the plum.
class _SidebarColors {
  const _SidebarColors._();

  static const background = BrandColors.plum;
  static const text = Color(0xFFF0E4EF);
  static const subtext = Color(0xFFD9C4DC);
  static const groupLabel = Color(0xFFD4B9D8);
  static const hover = Color(0x1FFFFFFF);
  static const divider = Color(0x24FFFFFF);
  static const activeBackground = Colors.white;
  static const activeText = BrandColors.plum;
  static const heading = Colors.white;
}

/// Whether the list of an area's screens is showing beside the icon strip.
/// Folded away, the page gets the width (docs/navigation-tabs.md). The
/// choice is remembered on this device (asked for 2026-11-17).
final navPanelOpenProvider = NotifierProvider<NavPanelOpen, bool>(NavPanelOpen.new);

class NavPanelOpen extends Notifier<bool> {
  static const _key = 'nav_panel_open';

  /// Set once the person folds or opens it, so a slow read of the saved
  /// choice never overrides what they just did.
  bool _chosen = false;

  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(keyValueStoreProvider).read(_key);
      if (saved != null && !_chosen && ref.mounted) state = saved == 'true';
    } catch (error) {
      // Not remembered is not broken: the list shows, as it always did.
      developer.log('Could not read whether the menu was folded', name: 'sidebar', error: error);
    }
  }

  void toggle() {
    _chosen = true;
    state = !state;
    _save(state);
  }

  Future<void> _save(bool open) async {
    try {
      await ref.read(keyValueStoreProvider).write(_key, '$open');
    } catch (error) {
      developer.log('Could not remember whether the menu was folded', name: 'sidebar', error: error);
    }
  }
}

/// The button that folds the list of screens away and brings it back - at
/// the left of the desktop top bar, where it is seen (asked for 2026-11-17).
/// Ctrl + B does the same (see AppShell).
class NavPanelToggle extends ConsumerWidget {
  const NavPanelToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(navPanelOpenProvider);

    return IconButton(
      key: const Key('nav-panel-toggle'),
      tooltip: open ? 'Hide the side panel (Ctrl + B)' : 'Show the side panel (Ctrl + B)',
      icon: Icon(open ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right),
      onPressed: () => ref.read(navPanelOpenProvider.notifier).toggle(),
    );
  }
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
            _Rail(groups: groups, selected: shown, onSelect: (group, button) => _openArea(group, user, shown, button)),
            if (panelOpen) ...[
              const VerticalDivider(width: 1, thickness: 1, color: _SidebarColors.divider),
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

  void _openArea(NavGroup group, AuthenticatedUser user, NavGroup shown, BuildContext button) {
    if (widget.inDrawer) {
      setState(() => _picked = group.label);
      return;
    }

    // Folded away, the area's screens pop up beside its icon and the panel
    // stays folded - whoever folded it wanted the width.
    if (!ref.read(navPanelOpenProvider)) {
      _showAreaMenu(group, user, button);
      return;
    }

    if (group.label == shown.label) return;

    context.go(group.itemsFor(user).first.path);
  }

  Future<void> _showAreaMenu(NavGroup group, AuthenticatedUser user, BuildContext button) async {
    final box = button.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topRight = box.localToGlobal(Offset(box.size.width + 6, 0), ancestor: overlay);
    final currentPath = GoRouterState.of(context).matchedLocation;
    final router = GoRouter.of(context);

    final path = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(topRight.dx, topRight.dy, overlay.size.width - topRight.dx, 0),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            group.label.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4),
          ),
        ),
        for (final item in group.itemsFor(user))
          PopupMenuItem<String>(
            key: Key('nav-flyout-${item.path}'),
            value: item.path,
            child: Row(
              children: [
                Icon(item.icon, size: 18),
                const SizedBox(width: 10),
                Text(item.label, style: TextStyle(fontWeight: currentPath == item.path ? FontWeight.w700 : null)),
              ],
            ),
          ),
      ],
    );
    if (path != null) router.go(path);
  }

  void _navigated() {
    _picked = null;
    widget.onNavigate?.call();
  }
}

/// The strip of area icons, each named underneath.
class _Rail extends StatelessWidget {
  const _Rail({required this.groups, required this.selected, required this.onSelect});

  final List<NavGroup> groups;
  final NavGroup selected;

  /// The area picked, and the icon's own context - for placing the list of
  /// its screens beside it when the panel is folded away.
  final void Function(NavGroup group, BuildContext button) onSelect;

  @override
  Widget build(BuildContext context) {
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
              child: const Padding(padding: EdgeInsets.all(2), child: School365Mark(size: 42)),
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
                    Builder(
                      builder: (button) => _RailButton(
                        group: group,
                        selected: group.label == selected.label,
                        onTap: () => onSelect(group, button),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
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
          hoverColor: _SidebarColors.hover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected ? _SidebarColors.activeBackground : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: selected
                        ? const [BoxShadow(color: Color(0x40160B1B), blurRadius: 12, offset: Offset(0, 4))]
                        : null,
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
                    color: selected ? _SidebarColors.heading : _SidebarColors.subtext,
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
        // Everyone at a school sees their school at the top (asked for
        // 2026-11-17); the platform's own staff see the product's name.
        if (user.schoolId != null)
          _SchoolHeader(user: user)
        else ...[
          // The name as the website writes it, "ai" in coral.
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'School365'),
                  TextSpan(
                    text: 'ai',
                    style: TextStyle(color: BrandColors.coral),
                  ),
                ],
              ),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                letterSpacing: -0.5,
                color: _SidebarColors.heading,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('School Management', style: TextStyle(fontSize: 13, color: _SidebarColors.subtext)),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(
            group.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
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

/// The school's logo and name at the top of the list of screens. Its
/// initials stand in until the school uploads a logo.
class _SchoolHeader extends StatelessWidget {
  const _SchoolHeader({required this.user});

  final AuthenticatedUser user;

  @override
  Widget build(BuildContext context) {
    final name = user.schoolName ?? 'Your school';

    return Container(
      key: const Key('nav-school'),
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _SidebarColors.divider)),
      ),
      child: Row(
        children: [
          SchoolLogoImage(logoUrl: user.schoolLogoUrl, schoolName: name, size: 44, onDark: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                height: 1.25,
                color: _SidebarColors.heading,
              ),
            ),
          ),
        ],
      ),
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
        elevation: selected ? 3 : 0,
        shadowColor: const Color(0x66160B1B),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: _SidebarColors.hover,
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: color,
                    ),
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
