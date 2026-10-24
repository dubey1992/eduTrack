import 'package:flutter/material.dart';

import 'auth_palette.dart';

/// The rounded, shadowed card shared by every public auth screen (login,
/// forgot password, reset password, the bus crew's sign-in) - factored out
/// so those screens can't visually drift apart from one another the way the
/// old admin-themed [ForgotPasswordScreen] once did from [LoginScreen].
/// White in the light theme, the dark theme's surface in the dark one
/// ([AuthPalette]).
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        key: const Key('auth-card'),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 60, offset: const Offset(0, 25))],
        ),
        // A plain Container has no Material ancestor of its own, which
        // interactive controls (e.g. CheckboxListTile) need for their ink
        // splashes/background - a Card would have provided one implicitly.
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
