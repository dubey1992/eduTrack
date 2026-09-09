import 'package:flutter/material.dart';

import '../marketing_colors.dart';

/// Shared sizing for every button on the marketing page, matching the
/// prototype's single `.btn{padding:11px 18px;border-radius:10px}` rule -
/// every button is the same size regardless of which section it's in.
const _kButtonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 11);
final _kButtonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
const _kButtonTextStyle = TextStyle(fontWeight: FontWeight.w700);

/// The solid blue CTA, e.g. "Join Early Access". Carries the prototype's
/// `.primary{box-shadow:0 8px 20px #2563eb26}` glow, which a plain
/// [FilledButton] doesn't have - without it the color reads flatter than
/// the source design.
class MarketingPrimaryButton extends StatelessWidget {
  const MarketingPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.background,
    this.foreground,
    this.glow = true,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  /// Defaults to [MarketingColors.primary] - overridden on the blue CTA
  /// banner, where the button is white with blue text instead.
  final Color? background;
  final Color? foreground;

  /// The prototype's glow only applies to its `.primary` (blue) buttons,
  /// not the white button on the already-blue CTA banner - pass false
  /// there to match.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? MarketingColors.primary;
    final style = FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: foreground ?? Colors.white,
      padding: _kButtonPadding,
      textStyle: _kButtonTextStyle,
      shape: _kButtonShape,
      elevation: 0,
    );
    final button = icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 18), label: Text(label));

    if (!glow) return button;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: button,
    );
  }
}

/// The outlined CTA, e.g. "Login" / "Watch Video".
class MarketingOutlineButton extends StatelessWidget {
  const MarketingOutlineButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: MarketingColors.primary,
      side: const BorderSide(color: MarketingColors.primary),
      padding: _kButtonPadding,
      textStyle: _kButtonTextStyle,
      shape: _kButtonShape,
    );

    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 18), label: Text(label));
  }
}
