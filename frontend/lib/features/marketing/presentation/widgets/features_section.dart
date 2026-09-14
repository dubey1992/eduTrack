import 'package:flutter/material.dart';

import '../marketing_colors.dart';
import 'marketing_wrap.dart';

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  static const _features = [
    ('☺', 'Student Management', 'Complete student records and academic details'),
    ('☺', 'Teacher Management', 'Staff records, workload and performance'),
    ('✓', 'Attendance', 'Real-time attendance with notifications'),
    ('¤', 'Academics', 'Timetable, exams and report cards'),
    ('⌣', 'Fees & Payments', 'Online and offline fee management'),
    ('🚌', 'Transport Management', 'Live tracking and route management'),
    ('✉', 'Communication', 'Connect with parents, teachers and students'),
    ('⚭', 'HR & Payroll', 'Leave, salary and staff management'),
    ('▥', 'Reports & Analytics', 'Insights for better decision making'),
    ('☰', 'Administration', 'Manage your school effortlessly'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 78),
      child: MarketingWrap(
        child: Column(
          children: [
            const SectionHead(
              eyebrow: 'EVERYTHING YOUR SCHOOL NEEDS',
              title: 'Powerful Features for Modern Schools',
              body: 'A complete solution to simplify school operations and enhance learning experiences.',
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = switch (constraints.maxWidth) {
                  < MarketingBreakpoints.mobile => 2,
                  < MarketingBreakpoints.tablet => 2,
                  _ => 5,
                };
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _features.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    // Two columns means narrower cards, and narrower cards
                    // wrap their body text onto more lines - a single fixed
                    // height for both layouts overflowed the phone one.
                    mainAxisExtent: columns == 5 ? 150 : 190,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 26,
                  ),
                  itemBuilder: (context, index) {
                    final (icon, title, body) = _features[index];
                    return _FeatureCard(
                      icon: icon,
                      title: title,
                      body: body,
                      color: MarketingColors.featureIconColors[index],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.icon, required this.title, required this.body, required this.color});

  final String icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(
            icon,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        const SizedBox(height: 5),
        // Flexible, so an unusually long line trims instead of overflowing
        // the fixed-height grid cell it lives in.
        Flexible(
          child: Text(
            body,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 4,
            style: const TextStyle(fontSize: 13, color: MarketingColors.subtle),
          ),
        ),
      ],
    );
  }
}

/// The centered "eyebrow + h2 + supporting paragraph" header shared by the
/// Features/Mobile/Web sections, matching the prototype's `.head`.
class SectionHead extends StatelessWidget {
  const SectionHead({super.key, required this.eyebrow, required this.title, required this.body});

  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 42),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              MarketingEyebrow(text: eyebrow),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: MarketingColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: MarketingColors.subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
