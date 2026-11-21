import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_shell.dart';
import 'change_password_dialog.dart';
import 'signed_in_devices_dialog.dart';

/// Settings > My Account (asked for 2026-11-21): the account's own actions
/// - the devices signed in, a new password, logging out - which used to sit
/// as icons in the top bar. Everyone also has them under their name in the
/// top bar; this page is where an administrator looking through Settings
/// finds them.
class MyAccountScreen extends ConsumerWidget {
  const MyAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActionCard(
                key: const Key('account-devices'),
                icon: Icons.devices_outlined,
                title: 'Signed-in devices',
                text: 'Every browser and phone signed in to your account. Sign out one you no longer use.',
                action: 'See devices',
                onPressed: () => showDialog(context: context, builder: (_) => const SignedInDevicesDialog()),
              ),
              const SizedBox(height: 14),
              _ActionCard(
                key: const Key('account-password'),
                icon: Icons.lock_outline,
                title: 'Change password',
                text: 'Choose a new password. You will need your current one.',
                action: 'Change password',
                onPressed: () => showDialog(context: context, builder: (_) => const ChangePasswordDialog()),
              ),
              const SizedBox(height: 14),
              _ActionCard(
                key: const Key('account-logout'),
                icon: Icons.logout,
                title: 'Log out',
                text: 'Sign out of School365ai on this device.',
                action: 'Log out',
                onPressed: () => confirmLogout(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 21, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
