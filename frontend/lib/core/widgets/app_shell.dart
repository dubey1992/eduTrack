import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/change_password_dialog.dart';
import '../../features/auth/presentation/signed_in_devices_dialog.dart';
import '../../features/my_trip/application/trip_mark_queue.dart';
import '../models/user_role.dart';
import '../routing/app_nav.dart';
import 'confirm_dialog.dart';
import 'responsive.dart';
import 'sidebar_nav.dart';
import 'user_avatar.dart';

/// The persistent app frame every authenticated screen renders inside:
/// sidebar (fixed on desktop, a drawer on mobile) + topbar (page title,
/// user info, logout) + the current route's content. Matches the
/// prototype's overall `<div class="app">` layout.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final heading = AppNav.headingFor(location);

    return ResponsiveBuilder(
      mobile: (context) => Scaffold(
        drawer: Drawer(child: SidebarNav(onNavigate: () => Navigator.of(context).pop())),
        appBar: AppBar(
          title: Text(heading?.title ?? ''),
          actions: [
            const _ProfileButton(),
            // The phone's only way out - the desktop topbar's actions are not
            // shown here, and a bus attendant lives on the phone layout.
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: () => _confirmLogout(context, ref),
            ),
          ],
        ),
        body: child,
      ),
      desktop: (context) => Scaffold(
        body: Row(
          children: [
            SizedBox(width: 255, child: SidebarNav()),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _Topbar(heading: heading),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Topbar extends ConsumerWidget {
  const _Topbar({required this.heading});

  final ({String title, String subtitle})? heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heading?.title ?? '', style: Theme.of(context).textTheme.titleLarge),
                if (heading != null)
                  Text(
                    heading!.subtitle,
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (user != null) ...[
            _Pill(text: user.role.label),
            const SizedBox(width: 8),
            _ProfileChip(name: user.name, photoUrl: user.photoUrl),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.devices_outlined),
            tooltip: 'Signed-in devices',
            onPressed: () => showDialog(context: context, builder: (_) => const SignedInDevicesDialog()),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Change password',
            // A dialog, not a page: changing a password is a two-minute
            // errand, and whoever is halfway through marking attendance
            // should get back to it rather than be navigated away.
            onPressed: () => showDialog(context: context, builder: (_) => const ChangePasswordDialog()),
          ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: () => _confirmLogout(context, ref)),
        ],
      ),
    );
  }
}

/// Signing out sits one pixel from Change Password and cannot be undone
/// without typing a password again - worth one question first.
///
/// A bus attendant may have trip marks on the phone that have not reached
/// the server (no signal); signing out throws them away, so they are told.
Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final isAttendant = ref.read(authNotifierProvider).value?.role == UserRole.busAttendant;
  final unsent = isAttendant ? await ref.read(tripMarkQueueProvider.notifier).waitingCount() : 0;
  if (!context.mounted) return;

  final confirmed = await confirmDialog(
    context,
    title: 'Log out?',
    message: unsent > 0
        ? '$unsent ${unsent == 1 ? 'mark has' : 'marks have'} not been sent yet. Sign out anyway? They will be lost.'
        : 'You will need to sign in again to get back to your school.',
    confirmLabel: 'Log out',
    cancelLabel: 'Stay signed in',
    isDestructive: unsent > 0,
  );

  if (confirmed) await ref.read(authNotifierProvider.notifier).logout();
}

/// The signed-in user's photo and name; opens My Profile.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'My profile',
      child: InkWell(
        key: const Key('header-profile-chip'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/profile'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(photoUrl: photoUrl, name: name, radius: 14),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's way to My Profile: the user's photo in the app bar.
class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    if (user == null) return const SizedBox.shrink();

    return IconButton(
      key: const Key('header-profile-button'),
      tooltip: 'My profile',
      icon: UserAvatar(photoUrl: user.photoUrl, name: user.name, radius: 14),
      onPressed: () => context.go('/profile'),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}
