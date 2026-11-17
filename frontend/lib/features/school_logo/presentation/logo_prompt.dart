import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/data/models/authenticated_user.dart';
import 'school_logo_card.dart';

/// The reminder a School Admin gets after signing in while the school has no
/// logo (docs/school-logo.md): every sign-in, until one is uploaded. It has
/// no "don't show again", because the logo is required.
Future<void> showLogoPrompt(BuildContext context, AuthenticatedUser user) {
  final schoolId = user.schoolId;
  if (schoolId == null) return Future.value();

  return showDialog<void>(
    context: context,
    builder: (context) => LogoPromptDialog(schoolId: schoolId, schoolName: user.schoolName ?? 'Your school'),
  );
}

class LogoPromptDialog extends StatelessWidget {
  const LogoPromptDialog({super.key, required this.schoolId, required this.schoolName});

  final int schoolId;
  final String schoolName;

  static const _uses = ['Menu for all staff', 'Fee receipts', 'Payslips', 'Report cards'];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AlertDialog(
      key: const Key('logo-prompt'),
      title: const Text('Add your school\'s logo'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your school profile is almost complete. Upload your logo to finish it. Your staff will see it '
                'when they sign in, and it is printed on every receipt, payslip and report card.',
              ),
              const SizedBox(height: 16),
              SchoolLogoCard(
                schoolId: schoolId,
                schoolName: schoolName,
                logoUrl: null,
                allowRemove: false,
                onChanged: (_) => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final use in _uses)
                    Chip(
                      label: Text(use, style: TextStyle(fontSize: 12, color: colors.muted)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('logo-prompt-later'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Remind me later'),
        ),
      ],
    );
  }
}

/// On the dashboard after "Remind me later": the profile is still not
/// complete, and stays said until the logo is uploaded.
class ProfileIncompleteBanner extends StatelessWidget {
  const ProfileIncompleteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      key: const Key('profile-incomplete-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Icon(Icons.school_outlined, color: colors.onWarningContainer),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your school profile is not complete.',
                  style: TextStyle(fontWeight: FontWeight.w600, color: colors.onWarningContainer),
                ),
                Text(
                  'Add your school\'s logo to finish it.',
                  style: TextStyle(fontSize: 13, color: colors.onWarningContainer),
                ),
              ],
            ),
          ),
          FilledButton(
            key: const Key('profile-incomplete-upload'),
            onPressed: () => context.go('/school-profile'),
            child: const Text('Upload logo'),
          ),
        ],
      ),
    );
  }
}
