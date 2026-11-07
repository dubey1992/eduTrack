import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/family_brand.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_account.dart';
import 'widgets/family_widgets.dart';

/// The five places of the parent's app (docs/parent-student-app.md,
/// "Navigation"): Home, Attendance, Bus, Fees, More.
enum FamilyPlace {
  home('/home', 'Home', Icons.home_outlined, Icons.home_rounded),
  attendance('/attendance', 'Attendance', Icons.event_available_outlined, Icons.event_available_rounded),
  bus('/bus', 'Bus', Icons.directions_bus_outlined, Icons.directions_bus_rounded),
  fees('/fees', 'Fees', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  more('/more', 'More', Icons.menu_rounded, Icons.menu_rounded);

  const FamilyPlace(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Every tab's frame: the child switcher at the top, the bottom bar below.
/// [showsChild] is false on More, which is about the parent, not a child.
class FamilyFrame extends ConsumerWidget {
  const FamilyFrame({super.key, required this.place, required this.child, this.showsChild = true});

  final FamilyPlace place;
  final Widget child;
  final bool showsChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(familySessionProvider).value;
    final children = account?.children ?? const <FamilyChild>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showsChild && children.isNotEmpty) _ChildSwitcher(children: children) else _PlainHeader(place: place),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('family-nav'),
        selectedIndex: place.index,
        onDestinationSelected: (index) => context.go(FamilyPlace.values[index].path),
        destinations: [
          for (final item in FamilyPlace.values)
            NavigationDestination(
              key: Key('family-nav-${item.name}'),
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _PlainHeader extends StatelessWidget {
  const _PlainHeader({required this.place});

  final FamilyPlace place;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(place.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// The child on screen, in their colour. With more than one child a tap
/// opens the list; with one, it simply says whose day this is.
class _ChildSwitcher extends ConsumerWidget {
  const _ChildSwitcher({required this.children});

  final List<FamilyChild> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedChildIndexProvider).clamp(0, children.length - 1);
    final current = children[index];
    final several = children.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Material(
        color: FamilyBrand.childColour(index).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('family-child-switcher'),
          borderRadius: BorderRadius.circular(16),
          onTap: several ? () => _choose(context, ref, index) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ChildAvatar(child: current, index: index),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(current.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                        [
                          if (current.className != null) current.className!,
                          if (several) '${children.length} children',
                        ].join(' · '),
                        style: TextStyle(fontSize: 13, color: context.appColors.muted),
                      ),
                    ],
                  ),
                ),
                if (several)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Switch',
                        style: TextStyle(color: FamilyBrand.childColour(index), fontWeight: FontWeight.w600),
                      ),
                      Icon(Icons.expand_more_rounded, color: FamilyBrand.childColour(index)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, int current) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Whose day?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            for (var i = 0; i < children.length; i++)
              ListTile(
                key: Key('family-child-${children[i].id}'),
                leading: ChildAvatar(child: children[i], index: i, size: 36),
                title: Text(children[i].fullName),
                subtitle: children[i].className == null ? null : Text(children[i].className!),
                trailing: i == current ? Icon(Icons.check_rounded, color: FamilyBrand.childColour(i)) : null,
                minTileHeight: 60,
                onTap: () => Navigator.of(context).pop(i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen != null) ref.read(selectedChildIndexProvider.notifier).select(chosen);
  }
}
