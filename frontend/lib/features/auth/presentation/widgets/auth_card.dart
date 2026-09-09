import 'package:flutter/material.dart';

import '../../../marketing/presentation/marketing_colors.dart';

/// The white, rounded, shadowed card shared by every public auth screen
/// (login, forgot password, reset password) - factored out so those screens
/// can't visually drift apart from one another the way the old
/// admin-themed [ForgotPasswordScreen] once did from [LoginScreen].
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: MarketingColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MarketingColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 60, offset: const Offset(0, 25)),
          ],
        ),
        // A plain Container has no Material ancestor of its own, which
        // interactive controls (e.g. CheckboxListTile) need for their ink
        // splashes/background - a Card would have provided one implicitly.
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
