import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/change_password_dialog.dart';
import '../routing/app_nav.dart';
import 'confirm_dialog.dart';
import 'responsive.dart';
import 'sidebar_nav.dart';

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
    final navItem = AppNav.findByPath(location);

    return ResponsiveBuilder(
      mobile: (context) => Scaffold(
        drawer: Drawer(child: SidebarNav(onNavigate: () => Navigator.of(context).pop())),
        appBar: AppBar(title: Text(navItem?.pageTitle ?? '')),
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
                  _Topbar(navItem: navItem),
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
  const _Topbar({required this.navItem});

  final NavItem? navItem;

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
                Text(navItem?.pageTitle ?? '', style: Theme.of(context).textTheme.titleLarge),
                if (navItem?.pageSubtitle != null)
                  Text(
                    navItem!.pageSubtitle,
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (user != null) ...[
            _Pill(text: user.role.label),
            const SizedBox(width: 8),
            _Pill(text: user.name),
            const SizedBox(width: 8),
          ],
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
Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await confirmDialog(
    context,
    title: 'Log out?',
    message: 'You will need to sign in again to get back to your school.',
    confirmLabel: 'Log out',
    cancelLabel: 'Stay signed in',
  );

  if (confirmed) await ref.read(authNotifierProvider.notifier).logout();
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
