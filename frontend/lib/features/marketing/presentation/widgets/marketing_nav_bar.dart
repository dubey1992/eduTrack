import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../marketing_colors.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';

/// The sticky top nav, matching the prototype's `.nav` - brand mark, anchor
/// links to each section (hidden below [MarketingBreakpoints.tablet], same
/// as the source `.links{display:none}` rule), and Login/Join Early Access
/// actions.
///
/// The bar is the first thing anyone sees, on whatever device they own, so it
/// is built so it cannot run off the edge: the brand and the actions are
/// fixed, and everything between them lives in the space that is left.
class MarketingNavBar extends StatelessWidget {
  const MarketingNavBar({super.key, required this.onNavigate, required this.onJoinEarlyAccess});

  /// label -> scroll callback, in display order.
  final Map<String, VoidCallback> onNavigate;
  final VoidCallback onJoinEarlyAccess;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MarketingColors.border)),
      ),
      child: MarketingWrap(
        // Measured from the space this bar actually has, not from the window.
        // MarketingWrap caps and pads its content, so the window can be wide
        // while the row inside is not - reading the window made the bar keep
        // links it had nowhere to put.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < MarketingBreakpoints.tablet;
            // On a phone the brand and both actions at full width already
            // exceed the screen, so the call to action shortens rather than
            // the bar spilling over the edge.
            final isTight = constraints.maxWidth < 480;

            return Row(
              children: [
                Flexible(child: _Brand(showTagline: !isCompact)),
                // The links take whatever is left after the brand and the
                // actions, and scroll inside it rather than pushing the bar
                // wider. Right-aligned, as they were, by reversing the scroll.
                Expanded(
                  child: isCompact
                      ? const SizedBox.shrink()
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            children: [
                              for (final entry in onNavigate.entries)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 13),
                                  child: InkWell(
                                    onTap: entry.value,
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 16),
                            ],
                          ),
                        ),
                ),
                MarketingOutlineButton(label: 'Login', onPressed: () => context.go('/login')),
                const SizedBox(width: 10),
                MarketingPrimaryButton(label: isTight ? 'Join' : 'Join Early Access', onPressed: onJoinEarlyAccess),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.showTagline});

  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: MarketingColors.primary, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: const Text('🎓', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 10),
        // mainAxisSize.min matters here: without it this Column stretches to
        // match the Row's full height (driven by the buttons on the other
        // end) and, with the default mainAxisAlignment.start, pins both lines
        // to the top of that taller box - reading as "text sits above the
        // logo's center" instead of actually being centered against it.
        // Flexible so the wordmark can ellipsize rather than push the row
        // wider than the space the bar gave it.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'School365ai',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, height: 1.1, color: MarketingColors.text),
              ),
              // The tagline is the first thing to drop on a narrow viewport
              // (same as the nav links) - it is decorative, and at 11px its own
              // natural width is wider than the brand name.
              if (showTagline)
                const Text(
                  'Smarter Schools. Brighter Futures.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.3, color: MarketingColors.subtle),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
