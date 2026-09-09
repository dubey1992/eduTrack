import 'package:flutter/material.dart';

/// Centers content at a max width of 1180px with a 20px side gutter,
/// matching the prototype's `.wrap{width:min(1180px,calc(100% - 40px))}`.
class MarketingWrap extends StatelessWidget {
  const MarketingWrap({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(padding: padding ?? const EdgeInsets.symmetric(horizontal: 20), child: child),
      ),
    );
  }
}

/// The small pill-shaped label used above section headings, e.g. "MOBILE APP".
class MarketingEyebrow extends StatelessWidget {
  const MarketingEyebrow({super.key, required this.text, this.color, this.background});

  final String text;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: background ?? const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? const Color(0xFF1D4ED8),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
