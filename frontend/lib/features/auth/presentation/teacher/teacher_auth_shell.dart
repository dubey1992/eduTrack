import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_brand.dart';
import '../../../../core/widgets/teacher_mark.dart';

/// The frame every signed-out screen of the Teacher app sits in: a teal band
/// carrying the mark and the screen's title, and the form on the page below
/// it, in one readable column on a tablet.
///
/// A phone screen, not the web's two-panel sign-in shrunk to fit.
class TeacherAuthShell extends StatelessWidget {
  const TeacherAuthShell({super.key, required this.title, required this.subtitle, required this.child, this.onBack});

  final String title;
  final String subtitle;
  final Widget child;

  /// Shows a back arrow in the band when given.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 48,
                                child: onBack == null
                                    ? null
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: IconButton(
                                          key: const Key('auth-back'),
                                          onPressed: onBack,
                                          tooltip: 'Back',
                                          color: Colors.white,
                                          icon: const Icon(Icons.arrow_back),
                                        ),
                                      ),
                              ),
                              const Row(
                                children: [
                                  TeacherMark(size: 44),
                                  SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'School365ai',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Text(
                                title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 15, height: 1.4),
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
                      child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 28), child: child),
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

/// A teal strip behind the status bar, over a page that scrolls under it.
///
/// The pages here start with a teal band that runs up behind the status bar;
/// once scrolled, the page's own text would run under the clock and the
/// battery. The strip keeps that edge teal however far the page has moved.
class TeacherStatusBarScrim extends StatelessWidget {
  const TeacherStatusBarScrim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: const IgnorePointer(child: ColoredBox(color: TeacherBrand.teal)),
        ),
      ],
    );
  }
}

/// The text style of the wide buttons here: the theme's own typeface, which
/// a bare TextStyle would replace.
TextStyle? teacherButtonText(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700);

/// A failure said in the app's own words, above the form: never a browser
/// alert, never only a snackbar that is gone before it is read.
class TeacherErrorBanner extends StatelessWidget {
  const TeacherErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.onDangerContainer, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wide button every signed-out screen ends on, with its own spinner.
class TeacherPrimaryButton extends StatelessWidget {
  const TeacherPrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: teacherButtonText(context),
        ),
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Theme.of(context).colorScheme.onPrimary),
              )
            : Text(label),
      ),
    );
  }
}
