import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BadgeTone { success, danger, warning, info, neutral }

/// Small pill-shaped status label, matching the prototype's `.badge`
/// component (used for user/school status, payment status, leave status,
/// attendance status, and more across every later phase).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (background, foreground) = switch (tone) {
      BadgeTone.success => (colors.successContainer, colors.onSuccessContainer),
      BadgeTone.danger => (colors.dangerContainer, colors.onDangerContainer),
      BadgeTone.warning => (colors.warningContainer, colors.onWarningContainer),
      BadgeTone.info => (colors.infoContainer, colors.onInfoContainer),
      BadgeTone.neutral => (
        Theme.of(context).colorScheme.surfaceContainerHighest,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
