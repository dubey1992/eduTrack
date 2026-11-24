import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/change_password_dialog.dart';
import '../../features/auth/presentation/signed_in_devices_dialog.dart';
import '../../features/my_trip/application/trip_mark_queue.dart';
import 'confirm_dialog.dart';
import '../l10n/l10n.dart';

/// The account's menu: My profile, the signed-in devices, a new password and
/// logging out. Opened from the profile at the foot of the side panel
/// (moved off the top bar 2026-11-21); [builder] draws what is clicked.
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key, required this.builder});

  /// The button, given the callback that opens and closes the menu.
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuAnchor(
      alignmentOffset: const Offset(8, 0),
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
      builder: (context, controller, _) =>
          builder(context, () => controller.isOpen ? controller.close() : controller.open()),
    );
  }
}

/// Signing out cannot be undone without typing a password again - worth one
/// question first.
///
/// A bus attendant may have trip marks on the phone that have not reached
/// the server (no signal); signing out throws them away, so they are told.
Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final isAttendant = ref.read(authNotifierProvider).value?.role.isCrew ?? false;
  final unsent = isAttendant ? await ref.read(tripMarkQueueProvider.notifier).waitingCount() : 0;
  if (!context.mounted) return;

  final l10n = context.l10n;
  final confirmed = await confirmDialog(
    context,
    title: l10n.coreLogOutTitle,
    message: unsent > 0 ? l10n.coreLogOutUnsent(unsent) : l10n.coreLogOutMessage,
    confirmLabel: l10n.coreLogOut,
    cancelLabel: l10n.coreStaySignedIn,
    isDestructive: unsent > 0,
  );

  if (confirmed) await ref.read(authNotifierProvider.notifier).logout();
}
