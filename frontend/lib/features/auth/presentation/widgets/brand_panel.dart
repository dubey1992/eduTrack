import 'package:flutter/material.dart';

import '../../../marketing/presentation/marketing_colors.dart';
import 'feature_item.dart';

/// The desktop login layout's left half - brand mark, tagline, hero message
/// and feature checklist, matching the prototype's `.hero` section. Only
/// ever shown on wide screens; [LoginScreen] skips it entirely on mobile so
/// the login form stays the first thing a phone user sees.
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  static const _features = ['Easy to use', 'Secure & Reliable', 'Access from anywhere', 'Built for modern schools'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below ~1400px (a "tablet"-ish width for this two-column layout,
        // since the shared app-wide desktop cutoff is 1100) the illustration
        // shrinks and the vertical rhythm tightens, rather than the fixed
        // sizing that only reads well on a genuinely wide desktop window.
        final isCompact = constraints.maxWidth < 1400;
        final illustrationHeight = isCompact ? 180.0 : 260.0;
        final heroFontSize = isCompact ? 40.0 : 54.0;

        return Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 24 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: MarketingColors.primary, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('🎓', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'School365ai',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: MarketingColors.text),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Smarter Schools. Brighter Futures.',
                style: TextStyle(fontSize: 13, color: MarketingColors.subtle),
              ),
              SizedBox(height: isCompact ? 20 : 32),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: heroFontSize,
                    height: 1.1,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w800,
                    color: MarketingColors.text,
                  ),
                  children: const [
                    TextSpan(text: 'Welcome to a '),
                    TextSpan(
                      text: 'Smarter School',
                      style: TextStyle(color: MarketingColors.primary),
                    ),
                    TextSpan(text: ' Ecosystem.'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Manage students, teachers, attendance, transport, communication '
                'and more — all in one powerful platform.',
                style: TextStyle(fontSize: 17, color: MarketingColors.muted, height: 1.4),
              ),
              SizedBox(height: isCompact ? 16 : 24),
              for (final feature in _features) FeatureItem(label: feature),
              SizedBox(height: isCompact ? 20 : 30),
              Container(
                height: illustrationHeight,
                decoration: BoxDecoration(color: MarketingColors.primaryLight, borderRadius: BorderRadius.circular(30)),
                alignment: Alignment.center,
                child: Text('🏫 👩‍🏫 👨‍🎓 📱', style: TextStyle(fontSize: isCompact ? 56 : 72)),
              ),
            ],
          ),
        );
      },
    );
  }
}
