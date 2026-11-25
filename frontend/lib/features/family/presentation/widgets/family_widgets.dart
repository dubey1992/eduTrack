import 'package:flutter/material.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/family_brand.dart';
import '../../data/models/family_account.dart';

/// The Family app's card: white on the soft ground, rounded, roomy.
class FamilyCard extends StatelessWidget {
  const FamilyCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A card's title row: an icon in a soft circle, a word beside it.
class CardHeading extends StatelessWidget {
  const CardHeading({super.key, required this.icon, required this.title, this.trailing, this.colour});

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tint = colour ?? Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: tint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        ?trailing,
      ],
    );
  }
}

/// A grey block the shape of what is coming - a loading screen that looks
/// like the screen, not a spinner (docs/parent-student-app.md, "five states").
class ShapePlaceholder extends StatefulWidget {
  const ShapePlaceholder({super.key, this.height = 16, this.width = double.infinity, this.radius = 8});

  final double height;
  final double width;
  final double radius;

  @override
  State<ShapePlaceholder> createState() => _ShapePlaceholderState();
}

class _ShapePlaceholderState extends State<ShapePlaceholder> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: reduceMotion ? 0.07 : 0.05 + 0.05 * _pulse.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A list of placeholder cards, for a whole screen loading.
class PlaceholderCards extends StatelessWidget {
  const PlaceholderCards({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('family-loading'),
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const FamilyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShapePlaceholder(height: 18, width: 140),
            SizedBox(height: 14),
            ShapePlaceholder(height: 28),
            SizedBox(height: 10),
            ShapePlaceholder(height: 14, width: 200),
          ],
        ),
      ),
    );
  }
}

/// Something went wrong: what, in plain words, and a way to try again.
class FamilyErrorView extends StatelessWidget {
  const FamilyErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is Failure && (error as Failure).code == Failure.network().code;
    final message = error is Failure ? (error as Failure).localizedMessage(context) : context.l10n.errorUnknown;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded, size: 44, color: context.appColors.muted),
            const SizedBox(height: 12),
            Text(
              offline ? context.l10n.familyNoConnection : context.l10n.familyCouldNotLoad,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('family-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.familyTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing to show, said kindly.
class FamilyEmptyView extends StatelessWidget {
  const FamilyEmptyView({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A child's initial on their own colour - the same colour on every screen,
/// so a parent of two never confuses them.
class ChildAvatar extends StatelessWidget {
  const ChildAvatar({super.key, required this.child, required this.index, this.size = 40, this.selected = false});

  final FamilyChild child;
  final int index;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colour = FamilyBrand.childColour(index);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
        boxShadow: selected ? [BoxShadow(color: colour.withValues(alpha: 0.45), blurRadius: 8)] : null,
      ),
      child: Text(
        child.initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42),
      ),
    );
  }
}

/// "Updated 8:42 AM" - and, when the last refresh failed, that this is the
/// earlier copy.
class UpdatedLine extends StatelessWidget {
  const UpdatedLine({super.key, required this.text, this.stale = false});

  final String text;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final colour = stale ? context.appColors.warning : context.appColors.muted;

    return Row(
      key: const Key('family-updated'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stale ? Icons.wifi_off_rounded : Icons.schedule_rounded, size: 14, color: colour),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: TextStyle(fontSize: 12, color: colour)),
        ),
      ],
    );
  }
}

/// "How is this worked out?" under a figure (docs/mobile-apps-review.md,
/// 4.1): one tap opens one line saying how the server counted it, in the
/// words a parent would use. Closed at first, so the figure leads.
class HowWorkedOut extends StatefulWidget {
  const HowWorkedOut({super.key, required this.explanation});

  final String explanation;

  @override
  State<HowWorkedOut> createState() => _HowWorkedOutState();
}

class _HowWorkedOutState extends State<HowWorkedOut> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          // At least 48 high, a comfortable target for a thumb; the words
          // wrap at large text rather than running off the screen (M11, 3.4).
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.l10n.familyHowWorkedOut,
                    style: TextStyle(fontSize: 13, color: muted, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) Text(widget.explanation, style: TextStyle(fontSize: 13, color: muted, height: 1.35)),
      ],
    );
  }
}
