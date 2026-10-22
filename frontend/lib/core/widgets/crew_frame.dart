import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import 'app_shell.dart';

/// The frame around the one screen the bus crew has.
///
/// [AppShell] is the office: a sidebar of every module, a profile chip, a
/// devices dialog. None of that belongs on a phone in a cradle, and the
/// crew cannot reach any of it anyway. So this is the whole chrome - who is
/// signed in, and the way out - and the trip fills the rest
/// (docs/driver-app.md).
class CrewFrame extends ConsumerWidget {
  const CrewFrame({super.key, required this.child});

  final Widget child;

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
    );
  }
}
