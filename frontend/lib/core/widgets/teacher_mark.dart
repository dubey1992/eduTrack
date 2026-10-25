import 'package:flutter/material.dart';

import '../theme/teacher_brand.dart';

/// The Teacher app's mark: an open book with an amber ribbon.
///
/// Drawn rather than shipped as an image so it is sharp at every size, takes
/// the colours of whatever it sits on, and can open on the splash. The
/// launcher icon (scripts/teacher_icon.py) draws the same shape.
class TeacherMark extends StatelessWidget {
  const TeacherMark({super.key, this.size = 64, this.tile = false, this.pageColor, this.lineColor, this.openness = 1});

  final double size;

  /// On a rounded teal tile, as on the launcher. Without it the book sits on
  /// whatever is behind it.
  final bool tile;

  /// The pages. White by default, which is right on teal.
  final Color? pageColor;

  /// The lines of text on the pages. The brand teal by default.
  final Color? lineColor;

  /// 0 is shut at the spine, 1 is open. The splash animates it.
  final double openness;

  @override
  Widget build(BuildContext context) {
    final book = CustomPaint(
      size: Size.square(size),
      painter: _BookPainter(
        pages: pageColor ?? Colors.white,
        lines: lineColor ?? TeacherBrand.teal,
        openness: openness.clamp(0, 1).toDouble(),
      ),
    );

    // Decorative: wherever it appears, the app's name is beside it in words.
    final mark = ExcludeSemantics(child: book);

    if (!tile) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: TeacherBrand.gradient,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: TeacherBrand.tealDeep.withValues(alpha: 0.25),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _BookPainter(
            pages: pageColor ?? Colors.white,
            lines: lineColor ?? TeacherBrand.teal,
            openness: openness.clamp(0, 1).toDouble(),
          ),
        ),
      ),
    );
  }
}

/// The book on a 100 x 100 grid: two curved pages meeting at the spine, three
/// lines on each, and the ribbon hanging from the right-hand page.
class _BookPainter extends CustomPainter {
  _BookPainter({required this.pages, required this.lines, required this.openness});

  final Color pages;
  final Color lines;
  final double openness;

  static const _spine = 50.0;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;
    canvas.save();
    canvas.scale(unit);

    // Pages fold out from the spine: every x is pulled towards it while shut.
    double x(double value) => _spine + (value - _spine) * (0.08 + 0.92 * openness);

    final paper = Paint()
      ..color = pages
      ..isAntiAlias = true;

    Path page(double outer) {
      return Path()
        ..moveTo(x(_spine), 34)
        ..quadraticBezierTo(x((_spine + outer) / 2), 20, x(outer), 25)
        ..lineTo(x(outer), 73)
        ..quadraticBezierTo(x((_spine + outer) / 2), 68, x(_spine), 82)
        ..close();
    }

    canvas.drawPath(page(8), paper);
    canvas.drawPath(page(92), paper);

    // The fold, a hair of shade down the spine.
    canvas.drawLine(
      Offset(_spine, 35),
      const Offset(_spine, 81),
      Paint()
        ..color = lines.withValues(alpha: 0.35)
        ..strokeWidth = 1.6,
    );

    if (openness > 0.55) {
      final ink = Paint()
        ..color = lines.withValues(alpha: ((openness - 0.55) / 0.45).clamp(0, 1).toDouble())
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (final y in [41.0, 50.0, 59.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(x(18), y - 4)
            ..quadraticBezierTo(x(31), y - 6.5, x(43), y - 1),
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(x(57), y - 1)
            ..quadraticBezierTo(x(69), y - 6.5, x(82), y - 4),
          ink,
        );
      }
    }

    // The ribbon, from the top edge of the right-hand page.
    final ribbon = Path()
      ..moveTo(x(70), 23.5)
      ..lineTo(x(79), 24.5)
      ..lineTo(x(79), 45)
      ..lineTo(x(74.5), 40.5)
      ..lineTo(x(70), 45)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = TeacherBrand.amber);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookPainter oldDelegate) =>
      oldDelegate.pages != pages || oldDelegate.lines != lines || oldDelegate.openness != openness;
}
