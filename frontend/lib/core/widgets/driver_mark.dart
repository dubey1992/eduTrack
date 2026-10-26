import 'package:flutter/material.dart';

/// The Driver app's mark: the shuttle from the splash animation, side on.
///
/// Drawn rather than shipped as an image so it is sharp at every size. The
/// launcher icon (scripts/driver_icon.py) draws the same shape on the same
/// 100 x 100 grid, so the icon on the phone and the logo in the app are one
/// drawing. Replaced the graduation cap on 2026-10-27.
class DriverMark extends StatelessWidget {
  const DriverMark({super.key, this.size = 44, this.tile = true});

  final double size;

  /// On the rounded brand-blue tile, as on the launcher. Without it the
  /// shuttle sits on whatever is behind it.
  final bool tile;

  static const blue = Color(0xFF2563EB);
  static const blueDeep = Color(0xFF1D4ED8);

  @override
  Widget build(BuildContext context) {
    final shuttle = CustomPaint(size: Size.square(tile ? size * 0.78 : size), painter: const _ShuttlePainter());

    // Decorative: the app's name is always beside it in words.
    if (!tile) return ExcludeSemantics(child: shuttle);

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.27),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [blue, blueDeep],
          ),
        ),
        child: shuttle,
      ),
    );
  }
}

class _ShuttlePainter extends CustomPainter {
  const _ShuttlePainter();

  static const white = Color(0xFFFFFFFF);
  static const skirt = Color(0xFFDBEAFE);
  static const glass = Color(0xFF1D4ED8);
  static const tyre = Color(0xFF0F172A);
  static const hub = Color(0xFFCBD5E1);
  static const amber = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;

    void box(double x0, double y0, double x1, double y1, double radius, Color colour) {
      canvas.drawRRect(
        RRect.fromLTRBR(x0 * unit, y0 * unit, x1 * unit, y1 * unit, Radius.circular(radius * unit)),
        Paint()..color = colour,
      );
    }

    void circle(double cx, double cy, double r, Color colour) {
      canvas.drawCircle(Offset(cx * unit, cy * unit), r * unit, Paint()..color = colour);
    }

    box(2, 22, 98, 74, 12, white);
    box(2, 58, 98, 74, 7, skirt);
    for (var i = 0; i < 4; i++) {
      final left = 20.0 + i * 19;
      box(left, 30, left + 13, 46, 3, glass);
    }
    box(6, 32, 14, 66, 2, glass);
    circle(93, 52, 4, amber);
    for (final cx in [24.0, 76.0]) {
      circle(cx, 75, 11, tyre);
      circle(cx, 75, 5, hub);
    }
  }

  @override
  bool shouldRepaint(covariant _ShuttlePainter oldDelegate) => false;
}
