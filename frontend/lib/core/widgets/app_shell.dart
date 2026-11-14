import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/academic_years/presentation/year_switch.dart';
import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/change_password_dialog.dart';
import '../../features/auth/presentation/signed_in_devices_dialog.dart';
import '../../features/my_trip/application/trip_mark_queue.dart';
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
    final area = AppNav.groupOf(location)?.label;

    return ResponsiveBuilder(
      mobile: (context) => Scaffold(
        drawer: Drawer(width: 304, child: SidebarNav(inDrawer: true, onNavigate: () => Navigator.of(context).pop())),
        appBar: AppBar(
          // Close to the menu button and a size smaller than the desktop's,
          // so "Dashboard" or "Timetable" fits beside the year and the
          // account buttons on a 360-pixel phone.
          titleSpacing: 4,
          title: Text(
            heading?.title ?? '',
            style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 18),
          ),
          actions: [
            const YearSwitch(compact: true),
            const _ProfileButton(),
            // The phone's only way out - the desktop topbar's actions are not
            // shown here, and a bus attendant lives on the phone layout.
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: () => confirmLogout(context, ref),
            ),
          ],
        ),
        body: child,
      ),
      desktop: (context) => Scaffold(
        body: Row(
          children: [
            // Sizes itself: the icon strip, plus the list of screens unless
            // it has been folded away.
            const SidebarNav(),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _Topbar(heading: heading, area: area),
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

/// The bar across the top of every desktop page (Warm Editorial,
/// 2026-11-14): the area as a small rose eyebrow - where you are - over the
/// page's serif title and what the page is for; the year, who is signed in
/// and the account's actions on the right.
class _Topbar extends ConsumerWidget {
  const _Topbar({required this.heading, required this.area});

  final ({String title, String subtitle})? heading;

  /// The sidebar area the page sits in.
  final String? area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    final theme = Theme.of(context);
    final title = heading?.title ?? '';
    // Not repeated when the page is its area's namesake ("Dashboard").
    final eyebrow = area != null && area != title ? area! : null;

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(28, 14, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null)
                  Text(
                    eyebrow.toUpperCase(),
                    key: const Key('topbar-area'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26, height: 1.2),
                ),
                if (heading != null)
                  Text(
                    heading!.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          // The year every year-based screen is showing (decided 2026-11-05).
          const YearSwitch(),
          const SizedBox(width: 8),
          if (user != null) ...[
            _Pill(text: user.role.label),
            const SizedBox(width: 8),
            _ProfileChip(name: user.name, photoUrl: user.photoUrl),
            const SizedBox(width: 8),
          ],
          _RoundAction(
            icon: Icons.devices_outlined,
            tooltip: 'Signed-in devices',
            onPressed: () => showDialog(context: context, builder: (_) => const SignedInDevicesDialog()),
          ),
          _RoundAction(
            icon: Icons.lock_outline,
            tooltip: 'Change password',
            // A dialog, not a page: changing a password is a two-minute
            // errand, and whoever is halfway through marking attendance
            // should get back to it rather than be navigated away.
            onPressed: () => showDialog(context: context, builder: (_) => const ChangePasswordDialog()),
          ),
          _RoundAction(icon: Icons.logout, tooltip: 'Log out', onPressed: () => confirmLogout(context, ref)),
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
Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final isAttendant = ref.read(authNotifierProvider).value?.role.isCrew ?? false;
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
        borderRadius: BorderRadius.circular(99),
        onTap: () => context.go('/profile'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(99),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// One of the account's actions in the top bar: a soft round button, as in
/// the redesign prototype.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        icon: Icon(icon, size: 19),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          hoverColor: colorScheme.secondary.withValues(alpha: 0.12),
          fixedSize: const Size(38, 38),
          minimumSize: const Size(38, 38),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
