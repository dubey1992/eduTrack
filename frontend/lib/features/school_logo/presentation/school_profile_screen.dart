import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_notifier.dart';
import 'school_logo_card.dart';

/// School Profile (docs/school-logo.md): the School Admin's own school, and
/// its logo - the one thing the profile needs to be complete.
class SchoolProfileScreen extends ConsumerWidget {
  const SchoolProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).value;
    final schoolId = user?.schoolId;
    final colors = context.appColors;
    final theme = Theme.of(context);

    if (user == null || schoolId == null) {
      return const Center(child: Text('School Profile is for the people who run a school.'));
    }

    final complete = user.schoolProfileComplete;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('School logo', style: theme.textTheme.titleLarge)),
                        _Status(complete: complete),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Shown at the top of the menu for everyone at ${user.schoolName ?? 'your school'}, '
                      'and printed on fee receipts, payslips and report cards.',
                      style: TextStyle(color: colors.muted),
                    ),
                    const SizedBox(height: 16),
                    SchoolLogoCard(
                      schoolId: schoolId,
                      schoolName: user.schoolName ?? 'Your school',
                      logoUrl: user.schoolLogoUrl,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      key: Key(complete ? 'school-profile-complete' : 'school-profile-incomplete'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: complete ? colors.successContainer : colors.warningContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        complete ? 'Profile complete' : 'Logo needed',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: complete ? colors.onSuccessContainer : colors.onWarningContainer,
        ),
      ),
    );
  }
}
