import 'package:flutter/material.dart';

import '../theme/family_brand.dart';

/// The Family app's mark: a house with a heart in its doorway.
///
/// Drawn rather than shipped as an image, so it is sharp at every size. The
/// launcher icon (scripts/family_icon.py) draws the same shape on the same
/// 100 x 100 grid.
class FamilyMark extends StatelessWidget {
  const FamilyMark({super.key, this.size = 64, this.tile = false, this.houseColor, this.heartColor});

  final double size;

  /// On a rounded blue tile, as on the launcher.
  final bool tile;

  /// White by default, which is right on blue.
  final Color? houseColor;

  final Color? heartColor;

  @override
  Widget build(BuildContext context) {
    final painter = _HousePainter(house: houseColor ?? Colors.white, heart: heartColor ?? FamilyBrand.coral);

    // Decorative: wherever it appears, the app's name is beside it in words.
    if (!tile) {
      return ExcludeSemantics(
        child: CustomPaint(size: Size.square(size), painter: painter),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: FamilyBrand.gradient,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: FamilyBrand.blueDeep.withValues(alpha: 0.25),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.13),
      child: ExcludeSemantics(child: CustomPaint(painter: painter)),
    );
  }
}

class _HousePainter extends CustomPainter {
  const _HousePainter({required this.house, required this.heart});

  final Color house;
  final Color heart;

  @override
  void paint(Canvas canvas, Size size) {
    Offset p(double x, double y) => Offset(x * size.width / 100, y * size.height / 100);

    final walls = Path()
      ..moveTo(p(50, 16).dx, p(50, 16).dy)
      ..lineTo(p(90, 49).dx, p(90, 49).dy)
      ..lineTo(p(78, 49).dx, p(78, 49).dy)
      ..lineTo(p(78, 84).dx, p(78, 84).dy)
      ..lineTo(p(22, 84).dx, p(22, 84).dy)
      ..lineTo(p(22, 49).dx, p(22, 49).dy)
      ..lineTo(p(10, 49).dx, p(10, 49).dy)
      ..close();
    canvas.drawPath(walls, Paint()..color = house);

    final fill = Paint()..color = heart;
    final radius = 8 * size.width / 100;
    canvas.drawCircle(p(42.5, 60), radius, fill);
    canvas.drawCircle(p(57.5, 60), radius, fill);
    final point = Path()
      ..moveTo(p(34.9, 62.6).dx, p(34.9, 62.6).dy)
      ..lineTo(p(65.1, 62.6).dx, p(65.1, 62.6).dy)
      ..lineTo(p(50, 77).dx, p(50, 77).dy)
      ..close();
    canvas.drawPath(point, fill);
  }

  @override
  bool shouldRepaint(_HousePainter oldDelegate) => oldDelegate.house != house || oldDelegate.heart != heart;
}
