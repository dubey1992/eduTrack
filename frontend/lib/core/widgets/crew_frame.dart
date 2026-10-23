import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import 'app_shell.dart';

/// The frame around the one screen the bus crew has.
///
/// [AppShell] is the office: a sidebar of every module, a profile chip, a
/// devices dialog. None of that belongs on a phone in a cradle, and the
/// crew cannot reach any of it anyway. So this is the whole chrome - who is
/// signed in, and the way out - and the trip fills the rest
/// (docs/driver-app.md).
/// The two places the bus crew can be.
enum CrewPlace {
  trip('/my-trip', 'Home', Icons.directions_bus_outlined, Icons.directions_bus_filled),
  profile('/profile', 'Profile', Icons.person_outline, Icons.person);

  const CrewPlace(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class CrewFrame extends ConsumerWidget {
  const CrewFrame({super.key, required this.child, required this.place});

  final Widget child;
  final CrewPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.name ?? 'My Trip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            // The same confirmation the office gets, which is the one that
            // counts the marks still waiting on the phone before throwing
            // them away.
            onPressed: () => confirmLogout(context, ref),
          ),
        ],
      ),
      body: SafeArea(child: child),
      // Two destinations, which is the whole app. A bar with one entry is
      // decoration; with twenty it is the office's sidebar, which is what
      // this build exists not to be (docs/driver-app.md).
      bottomNavigationBar: NavigationBar(
        key: const Key('crew-nav'),
        selectedIndex: CrewPlace.values.indexOf(place),
        onDestinationSelected: (index) {
          final chosen = CrewPlace.values[index];
          if (chosen != place) context.go(chosen.path);
        },
        destinations: [
          for (final destination in CrewPlace.values)
            NavigationDestination(
              key: Key('crew-nav-${destination.name}'),
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
