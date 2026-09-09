import 'package:flutter/material.dart';

import '../marketing_colors.dart';
import 'marketing_wrap.dart';
import 'phone_mockup.dart';

/// "Your School in Your Pocket" - matching the prototype's `.app` section:
/// copy + store badges on one side, a parent/teacher phone pair on the other.
class MobileAppSection extends StatelessWidget {
  const MobileAppSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 78),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -0.5),
          end: Alignment(1, 0.5),
          colors: [Color(0xFFECFDF5), Color(0xFFEFF6FF)],
        ),
      ),
      child: MarketingWrap(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < MarketingBreakpoints.tablet;
            final children = [const _MobileCopy(), const _PhonesRow()];
            if (isNarrow) {
              return Column(children: [children[0], const SizedBox(height: 40), children[1]]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 60),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileCopy extends StatelessWidget {
  const _MobileCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MarketingEyebrow(text: 'MOBILE APP'),
        const SizedBox(height: 12),
        const Text(
          'Your School in\nYour Pocket',
          style: TextStyle(fontSize: 34, height: 1.08, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        const SizedBox(height: 10),
        const Text(
          'Stay connected on the go with mobile apps for parents, teachers, students, and staff.',
          style: TextStyle(fontSize: 14, color: MarketingColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _StoreBadge(icon: '▶', line1: 'GET IT ON', line2: 'Google Play'),
            _StoreBadge(icon: '', line1: 'Download on the', line2: 'App Store'),
          ],
        ),
      ],
    );
  }
}

class _StoreBadge extends StatelessWidget {
  const _StoreBadge({required this.icon, required this.line1, required this.line2});

  final String icon;
  final String line1;
  final String line2;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$icon $line1', style: const TextStyle(color: Colors.white, fontSize: 9)),
          Text(
            line2,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PhonesRow extends StatelessWidget {
  const _PhonesRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 340,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(10, 0),
            child: const PhoneMockup(
              width: 175,
              height: 335,
              child: PhoneAppContent(
                greeting: 'Hello, Parent! 👋',
                subtitle: "Stay connected with your child's school.",
                quickActions: [('✓', 'Attendance'), ('¤', 'Results'), ('✉', 'Messages'), ('🚌', 'Transport')],
                footerTitle: "Today's Update",
                footerBody: '✓ Present',
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(-10, 0),
            child: const PhoneMockup(
              width: 175,
              height: 335,
              child: PhoneAppContent(
                greeting: 'Hello, Teacher! 👋',
                subtitle: 'Everything you need for today.',
                quickActions: [('✓', 'Attendance'), ('▦', 'Classes'), ('✉', 'Messages'), ('¤', 'Reports')],
                footerTitle: "Today's Classes",
                footerBody: 'Grade 6A · Mathematics',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
