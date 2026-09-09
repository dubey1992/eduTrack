import 'package:flutter/material.dart';

import '../marketing_colors.dart';

/// A phone-bezel frame matching the prototype's `.phone` illustration -
/// reused for the hero's overlapping phone and the mobile-app section's
/// parent/teacher pair, each given different content.
class PhoneMockup extends StatelessWidget {
  const PhoneMockup({super.key, required this.child, this.width = 145, this.height = 285});

  final Widget child;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.19),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.all(7),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Container(color: Colors.white, child: child),
      ),
    );
  }
}

/// The greeting + 2x2 quick-action grid + summary card content shared by
/// every phone mockup on this page, matching `.ps` / `.grid2` / `.pc`.
class PhoneAppContent extends StatelessWidget {
  const PhoneAppContent({
    super.key,
    required this.greeting,
    required this.subtitle,
    required this.quickActions,
    required this.footerTitle,
    required this.footerBody,
  });

  final String greeting;
  final String subtitle;
  final List<(String icon, String label)> quickActions;
  final String footerTitle;
  final String footerBody;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFF6FF), Colors.white],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: MarketingColors.text),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: MarketingColors.subtle, fontSize: 7)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: 2.3,
            children: [for (final action in quickActions) _PhoneCard(text: '${action.$1}\n${action.$2}')],
          ),
          const SizedBox(height: 10),
          _PhoneCard(
            richText: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 7, color: MarketingColors.text),
                children: [
                  TextSpan(
                    text: footerTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: '\n'),
                  TextSpan(text: footerBody),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({this.text, this.richText});

  final String? text;
  final Widget? richText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: MarketingColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.centerLeft,
      child: richText ?? Text(text!, style: const TextStyle(fontSize: 7, color: MarketingColors.text)),
    );
  }
}
