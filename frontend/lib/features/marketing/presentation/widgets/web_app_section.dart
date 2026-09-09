import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../marketing_colors.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';

/// "Complete Control on the Web" - a browser-chrome mockup of the school
/// dashboard beside a feature checklist, matching the prototype's `.web`
/// section.
class WebAppSection extends StatelessWidget {
  const WebAppSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 78),
      child: MarketingWrap(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < MarketingBreakpoints.tablet;
            const browser = _BrowserMockup();
            const copy = _WebCopy();
            if (isNarrow) {
              return const Column(children: [browser, SizedBox(height: 40), copy]);
            }
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: browser),
                SizedBox(width: 60),
                Expanded(child: copy),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrowserMockup extends StatelessWidget {
  const _BrowserMockup();

  static const _kpis = [('Students', '1,248'), ('Teachers', '86'), ('Attendance', '93%')];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(14)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 285,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 80, color: const Color(0xFF10203D)),
              Expanded(
                child: Container(
                  color: MarketingColors.background,
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'School Dashboard',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MarketingColors.text),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final kpi in _kpis)
                            Expanded(
                              child: Container(
                                margin: EdgeInsets.only(right: kpi == _kpis.last ? 0 : 7),
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: MarketingColors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(kpi.$1, style: const TextStyle(fontSize: 7, color: MarketingColors.subtle)),
                                    Text(
                                      kpi.$2,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: MarketingColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: MarketingColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              'Attendance Overview',
                              style: TextStyle(fontSize: 8, color: MarketingColors.text),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebCopy extends StatelessWidget {
  const _WebCopy();

  static const _checks = [
    'All features in one place',
    'Real-time insights',
    'Secure and scalable',
    'Access from anywhere',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MarketingEyebrow(text: 'WEB APPLICATION'),
        const SizedBox(height: 12),
        const Text(
          'Complete Control\non the Web',
          style: TextStyle(fontSize: 34, height: 1.08, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        const SizedBox(height: 10),
        const Text(
          'Powerful admin dashboard for school leaders and staff.',
          style: TextStyle(fontSize: 14, color: MarketingColors.muted),
        ),
        const SizedBox(height: 18),
        MarketingPrimaryButton(label: 'Explore Web Dashboard →', onPressed: () => context.go('/login')),
        const SizedBox(height: 18),
        for (final check in _checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '✓',
                  style: TextStyle(color: MarketingColors.success, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Text(check, style: const TextStyle(fontSize: 14, color: MarketingColors.muted)),
              ],
            ),
          ),
      ],
    );
  }
}
