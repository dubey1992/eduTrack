import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "Loading", in the School365ai mark: the blue tile with the graduation cap
/// from the homepage, bouncing gently while the cap tips and its tassel
/// swings. Used wherever a screen or a section waits - in the web portal and
/// both phone apps - in place of a plain spinning circle.
///
/// Not for the inside of a button: at 16 pixels a logo is a smudge, so a
/// busy Save button keeps its small circle.
///
/// Drawn rather than shipped as an image, so it is sharp at every size and
/// needs nothing to arrive over the network before it can show - which is
/// the whole point of a loader. web/index.html draws the same mark in HTML
/// for the moment before the app itself has loaded.
class BrandLoader extends StatefulWidget {
  const BrandLoader({super.key, this.size = 48, this.label});

  /// The tile's width and height. The bounce and its shadow take a little
  /// more room below it.
  final double size;

  /// Shown under the mark - the app's name, on a splash screen.
  final String? label;

  /// The homepage's own blue (MarketingColors.primary), and the deeper one
  /// the tile shades into.
  static const blue = Color(0xFF2563EB);
  static const blueDeep = Color(0xFF1D4ED8);

  /// The tassel - the gold of the cap on the homepage.
  static const gold = Color(0xFFFBBF24);

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Somebody who has asked their device for less motion gets the mark
    // standing still, which still says "this is School365ai, working".
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final label = widget.label;

    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _Bouncing(size: size, t: _controller.value),
            ),
            if (label != null) ...[
              SizedBox(height: size * 0.3),
              Text(
                label,
                style: TextStyle(
                  fontSize: math.max(16, size * 0.3),
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One frame of the bounce: [t] runs 0 to 1 and round again.
class _Bouncing extends StatelessWidget {
  const _Bouncing({required this.size, required this.t});

  final double size;
  final double t;

  @override
  Widget build(BuildContext context) {
    // Up and back down once per loop, easing at both ends like a real hop.
    final lift = math.sin(math.pi * t);
    final swing = math.sin(2 * math.pi * t);
    final rise = size * 0.14;

    return SizedBox(
      width: size,
      height: size + rise + size * 0.12,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // The shadow on the floor shrinks and fades as the tile rises.
          Positioned(
            bottom: 0,
            child: Container(
              width: size * (0.72 - 0.22 * lift),
              height: size * 0.08,
              decoration: BoxDecoration(
                color: BrandLoader.blueDeep.withValues(alpha: 0.22 - 0.12 * lift),
                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.08)),
              ),
            ),
          ),
          Positioned(
            top: rise * (1 - lift),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [BrandLoader.blue, BrandLoader.blueDeep],
                ),
                borderRadius: BorderRadius.circular(size * 0.27),
              ),
              child: CustomPaint(
                painter: _CapPainter(tilt: 0.1 * swing, tassel: 0.45 * math.cos(2 * math.pi * t)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The graduation cap, in white on the tile, with a gold tassel.
class _CapPainter extends CustomPainter {
  _CapPainter({required this.tilt, required this.tassel});

  /// How far the cap tips, in radians.
  final double tilt;

  /// How far the tassel swings from hanging straight down, in radians.
  final double tassel;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset at(double x, double y) => Offset(s * x, s * y);

    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(tilt);
    canvas.translate(-s / 2, -s / 2);

    // The cap under the board, a shade behind it so the board reads as on top.
    final crown = Path()
      ..moveTo(s * 0.3, s * 0.5)
      ..lineTo(s * 0.3, s * 0.66)
      ..quadraticBezierTo(s * 0.5, s * 0.78, s * 0.7, s * 0.66)
      ..lineTo(s * 0.7, s * 0.5)
      ..close();
    canvas.drawPath(crown, Paint()..color = Colors.white.withValues(alpha: 0.82));

    // The board: a diamond seen from just above.
    final board = Path()
      ..moveTo(s * 0.5, s * 0.24)
      ..lineTo(s * 0.86, s * 0.41)
      ..lineTo(s * 0.5, s * 0.58)
      ..lineTo(s * 0.14, s * 0.41)
      ..close();
    canvas.drawPath(board, Paint()..color = Colors.white);

    // The tassel: a cord from the button to the board's edge, then hanging
    // from there, swinging.
    final cord = Paint()
      ..color = BrandLoader.gold
      ..strokeWidth = math.max(1.2, s * 0.035)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final edge = at(0.78, 0.45);
    canvas.drawLine(at(0.5, 0.41), edge, cord);

    final length = s * 0.2;
    final end = edge + Offset(math.sin(tassel) * length, math.cos(tassel) * length);
    canvas.drawLine(edge, end, cord);
    canvas.drawCircle(end, s * 0.045, Paint()..color = BrandLoader.gold);
    canvas.drawCircle(at(0.5, 0.41), s * 0.03, Paint()..color = BrandLoader.gold);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CapPainter old) => old.tilt != tilt || old.tassel != tassel;
}
