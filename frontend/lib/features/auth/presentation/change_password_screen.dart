import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_notifier.dart';
import 'widgets/change_password_form.dart';

/// Where an account lands when it was created by a bulk import and handed a
/// generated password. The router holds it here - there is no sidebar and no
/// way past - until it picks a password of its own.
///
/// Anybody simply wanting to change theirs gets [ChangePasswordDialog]
/// instead, which keeps them where they were. This is the forced version, and
/// it is a whole screen precisely because there is nothing behind it.
class ChangePasswordScreen extends ConsumerWidget {
  const ChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mustChange = ref.watch(authNotifierProvider).value?.mustChangePassword ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        // Nothing to go back to while the change is being required.
        automaticallyImplyLeading: !mustChange,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ChangePasswordForm(
                  intro: mustChange
                      ? 'Your account was set up with a temporary password. Choose your own to continue.'
                      : 'Choose a new password for your account.',
                  onChanged: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
                    context.go('/dashboard');
                  },
                  footer: mustChange
                      ? (context, isSubmitting) => Center(
                          child: TextButton(
                            onPressed: isSubmitting ? null : () => ref.read(authNotifierProvider.notifier).logout(),
                            child: const Text('Sign out instead'),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
