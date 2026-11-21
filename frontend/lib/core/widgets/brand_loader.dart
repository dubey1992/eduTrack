import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand_tokens.dart';
import 'school365_mark.dart';

/// "Loading", in the School365AI mark: the S under its cap (2026-11-21) on a
/// white tile, bouncing gently and tipping a little as it lands. Used
/// wherever a screen or a section waits - in the web portal and both phone
/// apps - in place of a plain spinning circle.
///
/// Not for the inside of a button: at 16 pixels a logo is a smudge, so a
/// busy Save button keeps its small circle.
///
/// The mark is bundled with the app (assets/brand), so it needs nothing to
/// arrive over the network before it can show - which is the whole point of
/// a loader. web/index.html shows the same mark for the moment before the
/// app itself has loaded.
class BrandLoader extends StatefulWidget {
  const BrandLoader({super.key, this.size = 48, this.label});

  /// The tile's width and height. The bounce and its shadow take a little
  /// more room below it.
  final double size;

  /// Shown under the mark - the app's name, on a splash screen.
  final String? label;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Somebody who has asked their device for less motion gets the mark
    // standing still, which still says "this is School365AI, working".
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
                color: BrandColors.deep.withValues(alpha: 0.18 - 0.1 * lift),
                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.08)),
              ),
            ),
          ),
          Positioned(
            top: rise * (1 - lift),
            child: Transform.rotate(
              angle: 0.06 * swing,
              child: Container(
                width: size,
                height: size,
                padding: EdgeInsets.all(size * 0.12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(size * 0.24),
                  border: Border.all(color: BrandColors.line),
                ),
                child: School365Mark(size: size * 0.76),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
