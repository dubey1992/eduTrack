import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/teacher_brand.dart';
import '../../../../core/widgets/teacher_mark.dart';
import 'teacher_auth_shell.dart';

/// What the app is, before anybody signs in (docs/teacher-app.md).
///
/// Written for a teacher between periods: what it does for them in four
/// lines, how they sign in, and what to do if they have no account yet.
/// Every line is something the app does today.
class TeacherWelcomeScreen extends StatelessWidget {
  const TeacherWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: TeacherStatusBarScrim(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: TeacherBrand.gradient,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const TeacherMark(key: Key('welcome-mark'), size: 72),
                              const SizedBox(height: 18),
                              Text(
                                l10n.staffWelcomeHeadline,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.staffWelcomeIntro,
                                style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 15.5, height: 1.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Point(
                              icon: Icons.fingerprint,
                              title: l10n.staffWelcomeCheckInTitle,
                              body: l10n.staffWelcomeCheckInBody,
                            ),
                            _Point(
                              icon: Icons.today_outlined,
                              title: l10n.staffWelcomeTodayTitle,
                              body: l10n.staffWelcomeTodayBody,
                            ),
                            _Point(
                              icon: Icons.task_alt,
                              title: l10n.staffWelcomeRegisterTitle,
                              body: l10n.staffWelcomeRegisterBody,
                            ),
                            _Point(
                              icon: Icons.event_available_outlined,
                              title: l10n.staffWelcomeCalendarTitle,
                              body: l10n.staffWelcomeCalendarBody,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                key: const Key('welcome-sign-in'),
                                onPressed: () => context.go('/login'),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: teacherButtonText(context),
                                ),
                                child: Text(l10n.staffSignIn),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.staffWelcomeNewHere,
                              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thing the app does, said once.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
