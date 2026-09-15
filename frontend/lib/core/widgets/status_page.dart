import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A full-screen "something is not normal" page: brand lockup, a badge, a
/// headline, an explanation and the way out.
///
/// The Flutter twin of `backend/resources/views/errors/layout.blade.php`, so
/// the page a person meets inside the app and the one the web server hands
/// them look like the same product. Change one, change the other.
class StatusPage extends StatelessWidget {
  const StatusPage({
    super.key,
    required this.badge,
    required this.headline,
    required this.body,
    this.actions = const [],
    this.detail,
  });

  /// The small pill above the headline: 'Error 404', 'Scheduled maintenance'.
  final String badge;

  final String headline;

  /// A sentence or two, in plain words. Never a stack trace.
  final String body;

  final List<Widget> actions;

  /// Quieter text below a divider - the path that was not found, when to come
  /// back. Optional: not every page has more to say.
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BrandLockup(muted: appColors.muted),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: appColors.infoContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(color: appColors.onInfoContainer, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        headline,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                      ),
                      const SizedBox(height: 12),
                      Text(body, style: TextStyle(color: appColors.muted, height: 1.6)),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Wrap(spacing: 12, runSpacing: 12, children: actions),
                      ],
                      if (detail != null) ...[
                        const SizedBox(height: 24),
                        Divider(height: 1, color: colors.outlineVariant),
                        const SizedBox(height: 20),
                        DefaultTextStyle.merge(
                          style: TextStyle(color: appColors.muted, fontSize: 14),
                          child: detail!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '© ${DateTime.now().year} School365ai',
                    style: TextStyle(color: appColors.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.muted});

  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: const Text('🎓', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        // Flexible, not bare: the tagline is wider than a narrow phone and
        // would otherwise run the whole lockup off the edge.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'School365ai',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Smarter Schools. Brighter Futures.',
                style: TextStyle(color: muted, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
