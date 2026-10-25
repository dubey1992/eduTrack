import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../models/module_access.dart';
import 'app_shell.dart';
import 'teacher_mark.dart';

/// The frame around the teacher app's screens (docs/teacher-app.md, T0).
///
/// Like [CrewFrame] and unlike [AppShell]: who is signed in, the way out,
/// and a bottom bar with the places a teacher goes - not the office's
/// sidebar of twenty modules. Tabs are added here as their phases land;
/// a tab with nothing behind it is decoration, so T0 has the two that
/// exist.
/// The places a teacher can be, in the order the bar shows them.
enum TeacherPlace {
  today('/today', 'Today', Icons.today_outlined, Icons.today),
  leave('/leave', 'Leave', Icons.event_note_outlined, Icons.event_note),
  profile('/profile', 'Me', Icons.person_outline, Icons.person);

  const TeacherPlace(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class TeacherFrame extends ConsumerWidget {
  const TeacherFrame({super.key, required this.child, required this.place});

  final Widget child;
  final TeacherPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    // A school that switched leave off has no Leave tab, rather than one
    // that opens on "switched off".
    final places = [
      for (final candidate in TeacherPlace.values)
        if (candidate != TeacherPlace.leave || (user?.canView(AppModules.leave) ?? false)) candidate,
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const TeacherMark(size: 34, tile: true),
            const SizedBox(width: 12),
            Flexible(child: Text(user?.name ?? 'School365ai', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('teacher-logout'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => confirmLogout(context, ref),
          ),
        ],
      ),
      // One column everywhere. A tablet in a staff room gets a readable
      // width in the middle rather than a register stretched edge to edge;
      // a phone is narrower than this and sees no difference.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('teacher-nav'),
        selectedIndex: places.indexOf(place).clamp(0, places.length - 1),
        onDestinationSelected: (index) {
          final chosen = places[index];
          if (chosen != place) context.go(chosen.path);
        },
        destinations: [
          for (final destination in places)
            NavigationDestination(
              key: Key('teacher-nav-${destination.name}'),
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
