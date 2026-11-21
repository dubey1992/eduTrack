import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/academic_years/presentation/year_switch.dart';
import '../../features/auth/application/auth_notifier.dart';
import '../../features/school_logo/application/school_logo_controller.dart';
import '../../features/school_logo/presentation/logo_prompt.dart';
import '../../features/school_logo/presentation/school_logo_image.dart';
import '../routing/app_nav.dart';
import 'account_menu.dart';
import 'responsive.dart';
import 'sidebar_nav.dart';
import 'user_avatar.dart';

export 'account_menu.dart' show confirmLogout;

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
/// page's title and what the page is for; on the right the year and, in the
/// corner, the school's logo and name. Kept clean on purpose (asked for
/// 2026-11-21): who is signed in lives at the foot of the side panel.
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
          // The school - its logo and its name - in the corner (asked for
          // 2026-11-21; it used to head the side panel). Who is signed in,
          // and their role, are at the foot of the side panel.
          if (user?.schoolId != null) ...[
            const SizedBox(width: 14),
            _SchoolCorner(name: user!.schoolName ?? 'Your school', logoUrl: user.schoolLogoUrl),
          ],
        ],
      ),
    );
  }
}

/// The school the signed-in person belongs to: its logo, and its name beside
/// it on up to two lines, in the top bar's right corner.
class _SchoolCorner extends StatelessWidget {
  const _SchoolCorner({required this.name, required this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('header-school'),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SchoolLogoImage(key: const Key('header-school-logo'), logoUrl: logoUrl, schoolName: name, size: 42),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              name,
              key: const Key('header-school-name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(height: 1.25),
            ),
          ),
        ],
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
