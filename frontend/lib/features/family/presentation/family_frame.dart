import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/family_brand.dart';
import '../application/family_notifiers.dart';
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

  /// [label] in the parent's language.
  String words(AppLocalizations l10n) => switch (this) {
    FamilyPlace.home => l10n.familyTabHome,
    FamilyPlace.attendance => l10n.familyTabAttendance,
    FamilyPlace.bus => l10n.familyTabBus,
    FamilyPlace.fees => l10n.familyTabFees,
    FamilyPlace.more => l10n.familyTabMore,
  };
}

/// The tabs this family has: Bus only when the school runs transport and
/// carries one of their children; Fees only when the school uses fees. A tab
/// that can only ever say "nothing here" is left out, as the staff app does.
List<FamilyPlace> placesFor(FamilyAccount? account) {
  if (account == null) return FamilyPlace.values;

  return [
    for (final place in FamilyPlace.values)
      if (switch (place) {
        FamilyPlace.bus => account.features.transport && account.anyChildOnTransport,
        FamilyPlace.fees => account.features.fees,
        _ => true,
      })
        place,
  ];
}

/// Every tab's frame: the child switcher and the bell at the top, the
/// bottom bar below. [showsChild] is false on More, which is about the
/// parent, not a child.
///
/// Android's back button goes Home from any other tab, and only leaves the
/// app from Home - the way a phone app is expected to behave.
class FamilyFrame extends ConsumerWidget {
  const FamilyFrame({super.key, required this.place, required this.child, this.showsChild = true});

  final FamilyPlace place;
  final Widget child;
  final bool showsChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(familySessionProvider).value;
    final children = account?.children ?? const <FamilyChild>[];
    final places = placesFor(account);
    final index = places.indexOf(place);

    return PopScope(
      canPop: place == FamilyPlace.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(FamilyPlace.home.path);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: showsChild && children.isNotEmpty
                        ? _ChildSwitcher(children: children)
                        : _PlainHeader(place: place),
                  ),
                  const Padding(padding: EdgeInsets.only(right: 8), child: _NoticesBell()),
                ],
              ),
              Expanded(child: child),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          key: const Key('family-nav'),
          // A hidden tab reached by its address still shows; the bar then
          // simply has nothing lit.
          selectedIndex: index < 0 ? 0 : index,
          indicatorColor: index < 0 ? Colors.transparent : null,
          onDestinationSelected: (chosen) => context.go(places[chosen].path),
          destinations: [
            for (final item in places)
              NavigationDestination(
                key: Key('family-nav-${item.name}'),
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.words(context.l10n),
              ),
          ],
        ),
      ),
    );
  }
}

/// The school's messages, with how many are unread - on every tab, as the
/// staff app's bell is, because they are why a parent opens the app.
class _NoticesBell extends ConsumerWidget {
  const _NoticesBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(familyNoticesProvider).value?.unreadCount ?? 0;

    return IconButton(
      key: const Key('family-bell'),
      tooltip: unread > 0 ? context.l10n.familyNewNoticesCount(unread) : context.l10n.familyNotices,
      onPressed: () async {
        await context.push('/notices');
        // Read again on the way back: some were opened there.
        ref.invalidate(familyNoticesProvider);
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined, size: 26),
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
        child: Text(place.words(context.l10n), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 6),
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
                          if (several) context.l10n.familyChildrenCount(children.length),
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
                        context.l10n.familySwitch,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.familyWhoseDay,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
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
