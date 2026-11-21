import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/academic_years/presentation/year_switch.dart';
import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/change_password_dialog.dart';
import '../../features/auth/presentation/signed_in_devices_dialog.dart';
import '../../features/my_trip/application/trip_mark_queue.dart';
import '../../features/school_logo/application/school_logo_controller.dart';
import '../../features/school_logo/presentation/logo_prompt.dart';
import '../../features/school_logo/presentation/school_logo_image.dart';
import '../routing/app_nav.dart';
import 'confirm_dialog.dart';
import 'responsive.dart';
import 'sidebar_nav.dart';
import 'user_avatar.dart';

/// The persistent app frame every authenticated screen renders inside:
/// sidebar (fixed on desktop, a drawer on mobile) + topbar (page title,
/// user info, logout) + the current route's content. Matches the
/// prototype's overall `<div class="app">` layout.
///
/// It is also where a School Admin is asked for the school's logo, once per
/// sign-in, while the school has none (docs/school-logo.md).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  Widget build(BuildContext context) {
    _askForLogoOnce();
    final child = widget.child;
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

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl + B folds the side panel, as in most editors (asked for
  /// 2026-11-17). Listened for app-wide rather than through a Focus here: a
  /// click on an empty part of the page takes the focus away from the shell,
  /// and the shortcut should still work then.
  bool _onKey(KeyEvent event) {
    final ctrlB =
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyB &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed;
    if (!ctrlB || !mounted) return false;

    ref.read(navPanelOpenProvider.notifier).toggle();
    return true;
  }

  /// After the first frame of a signed-in session, a School Admin whose
  /// school has no logo is asked for one. Marked as asked before the dialog
  /// opens, so a rebuild underneath it never opens a second.
  void _askForLogoOnce() {
    final user = ref.watch(authNotifierProvider).value;
    if (!needsLogoPrompt(user) || ref.read(logoPromptShownProvider)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(logoPromptShownProvider)) return;
      final current = ref.read(authNotifierProvider).value;
      if (!needsLogoPrompt(current)) return;

      ref.read(logoPromptShownProvider.notifier).markShown();
      showLogoPrompt(context, current!);
    });
  }
}

/// The bar across the top of every desktop page (School365AI design,
/// 2026-11-21): the area as a small teal eyebrow - where you are - over the
/// page's title and what the page is for; on the right the year, the role,
/// who is signed in (a menu with the account's actions) and, in the corner,
/// the school's own logo.
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
      padding: const EdgeInsets.fromLTRB(12, 14, 20, 14),
      child: Row(
        children: [
          const NavPanelToggle(),
          const SizedBox(width: 8),
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
            // The account's actions sit behind the name (asked for
            // 2026-11-21); administrators also find them under Settings.
            _AccountMenu(name: user.name, photoUrl: user.photoUrl),
            // The school's own logo in the corner (asked for 2026-11-21).
            if (user.schoolId != null) ...[
              const SizedBox(width: 14),
              Tooltip(
                message: user.schoolName ?? 'Your school',
                child: SchoolLogoImage(
                  key: const Key('header-school-logo'),
                  logoUrl: user.schoolLogoUrl,
                  schoolName: user.schoolName ?? 'Your school',
                  size: 42,
                ),
              ),
            ],
          ],
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

/// Who is signed in - photo and name - opening the account's menu: My
/// profile, the signed-in devices, a new password, and logging out.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        MenuItemButton(
          key: const Key('account-menu-profile'),
          leadingIcon: const Icon(Icons.person_outline, size: 19),
          onPressed: () => context.go('/profile'),
          child: const Text('My profile'),
        ),
        MenuItemButton(
          key: const Key('account-menu-devices'),
          leadingIcon: const Icon(Icons.devices_outlined, size: 19),
          onPressed: () => showDialog(context: context, builder: (_) => const SignedInDevicesDialog()),
          child: const Text('Signed-in devices'),
        ),
        MenuItemButton(
          key: const Key('account-menu-password'),
          leadingIcon: const Icon(Icons.lock_outline, size: 19),
          // A dialog, not a page: changing a password is a two-minute
          // errand, and whoever is halfway through marking attendance
          // should get back to it rather than be navigated away.
          onPressed: () => showDialog(context: context, builder: (_) => const ChangePasswordDialog()),
          child: const Text('Change password'),
        ),
        const Divider(height: 1),
        MenuItemButton(
          key: const Key('account-menu-logout'),
          leadingIcon: const Icon(Icons.logout, size: 19),
          onPressed: () => confirmLogout(context, ref),
          child: const Text('Log out'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Your account',
        child: InkWell(
          key: const Key('header-profile-chip'),
          borderRadius: BorderRadius.circular(99),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
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
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 18, color: colorScheme.onSurfaceVariant),
              ],
            ),
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
