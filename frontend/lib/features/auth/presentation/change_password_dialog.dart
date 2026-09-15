import 'package:flutter/material.dart';

import 'widgets/change_password_form.dart';

/// Changing your own password without leaving what you were doing.
///
/// Opened from the header. The forced version - an imported account that has
/// to pick a password before anything else opens - is a full screen instead
/// (ChangePasswordScreen), because there is deliberately nothing behind it to
/// go back to.
class ChangePasswordDialog extends StatelessWidget {
  const ChangePasswordDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: ChangePasswordForm(
            intro: 'Choose a new password for your account.',
            onChanged: () {
              // Taken before the pop: afterwards this context is on its way
              // out and cannot find the messenger.
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              messenger.showSnackBar(const SnackBar(content: Text('Password changed.')));
            },
            footer: (context, isSubmitting) => Center(
              child: TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
