import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../marketing_colors.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';

/// The sticky top nav, matching the prototype's `.nav` - brand mark, anchor
/// links to each section (hidden below [MarketingBreakpoints.tablet], same
/// as the source `.links{display:none}` rule), and Login/Join Early Access
/// actions.
class MarketingNavBar extends StatelessWidget {
  const MarketingNavBar({super.key, required this.onNavigate, required this.onJoinEarlyAccess});

  /// label -> scroll callback, in display order.
  final Map<String, VoidCallback> onNavigate;
  final VoidCallback onJoinEarlyAccess;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < MarketingBreakpoints.tablet;

    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MarketingColors.border)),
      ),
      child: MarketingWrap(
        child: Row(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: MarketingColors.primary, borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: const Text('🎓', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                // mainAxisSize.min matters here: without it this Column
                // stretches to match the Row's full height (driven by the
                // buttons on the other end) and, with the default
                // mainAxisAlignment.start, pins both lines to the top of
                // that taller box - reading as "text sits above the logo's
                // center" instead of actually being centered against it.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'School365ai',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 1.1,
                        color: MarketingColors.text,
                      ),
                    ),
                    // The tagline is the first thing to drop on a narrow
                    // viewport (same as the nav links) - it's decorative,
                    // and at 11px its own natural width is wider than the
                    // brand name, so keeping it around was what pushed the
                    // whole bar past a plain Row's available space.
                    if (!isCompact)
                      const Text(
                        'Smarter Schools. Brighter Futures.',
                        style: TextStyle(fontSize: 11, height: 1.3, color: MarketingColors.subtle),
                      ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            if (!isCompact) ...[
              for (final entry in onNavigate.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: InkWell(
                    onTap: entry.value,
                    child: Text(entry.key, style: const TextStyle(fontSize: 14, color: Color(0xFF334155))),
                  ),
                ),
              const SizedBox(width: 16),
            ],
            MarketingOutlineButton(label: 'Login', onPressed: () => context.go('/login')),
            const SizedBox(width: 10),
            MarketingPrimaryButton(label: 'Join Early Access', onPressed: onJoinEarlyAccess),
          ],
        ),
      ),
    );
  }
}
