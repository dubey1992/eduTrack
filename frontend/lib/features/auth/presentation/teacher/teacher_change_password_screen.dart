import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_notifier.dart';
import '../widgets/change_password_form.dart';
import 'teacher_auth_shell.dart';

/// Where a teacher lands who was given a temporary password - one made by a
/// staff import (docs/imports.md). The router keeps them here until they
/// choose their own, exactly as the portal does; then Today.
class TeacherChangePasswordScreen extends ConsumerWidget {
  const TeacherChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TeacherAuthShell(
      title: 'Choose your password',
      subtitle: 'Your account was set up with a temporary password. Choose your own to continue.',
      child: ChangePasswordForm(
        submitLabel: 'Save password',
        onChanged: () {
          // The session now says the change is done, and the router moves on
          // to Today by itself.
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
        },
        footer: (context, isSubmitting) => Center(
          child: TextButton(
            key: const Key('change-password-sign-out'),
            onPressed: isSubmitting ? null : () => ref.read(authNotifierProvider.notifier).logout(),
            child: const Text('Sign out instead'),
          ),
        ),
      ),
    );
  }
}
