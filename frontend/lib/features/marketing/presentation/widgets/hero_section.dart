import 'package:flutter/material.dart';

import '../marketing_colors.dart';
import 'dashboard_mockup.dart';
import 'early_access_form.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';
import 'phone_mockup.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 58, bottom: 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7FBFF), MarketingColors.background],
        ),
      ),
      child: MarketingWrap(
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < MarketingBreakpoints.tablet;
                if (isNarrow) {
                  return const Column(children: [_HeroCopy(), SizedBox(height: 30), _HeroVisual()]);
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 46, child: _HeroCopy()),
                    Expanded(flex: 54, child: _HeroVisual()),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            const _StatsRow(),
          ],
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MarketingEyebrow(text: 'A Complete School Management Platform'),
        const SizedBox(height: 16),
        Text(
          'Run Your School Smarter, Together.',
          style: TextStyle(
            fontSize: 46,
            height: 1.05,
            letterSpacing: -1.5,
            fontWeight: FontWeight.w800,
            color: MarketingColors.text,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Students, Teachers, Academics, Attendance, Transport, Communication, '
          'Payroll and more — all in one simple and powerful platform.',
          style: TextStyle(fontSize: 17, color: Color(0xFF334155), height: 1.4),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MarketingPrimaryButton(label: 'Join Early Access →', onPressed: () => showEarlyAccessDialog(context)),
            MarketingOutlineButton(
              label: 'Watch Video',
              icon: Icons.play_arrow,
              onPressed: () => showEarlyAccessDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AvatarStack(),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Trusted by forward-thinking school leaders worldwide.',
                style: TextStyle(fontSize: 13, color: MarketingColors.subtle),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: 30 + 4 * 24,
      child: Stack(
        children: [
          for (var i = 0; i < 4; i++)
            Positioned(
              left: i * 24.0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  gradient: const LinearGradient(colors: [Color(0xFFBFDBFE), Color(0xFF99F6E4)]),
                ),
              ),
            ),
          Positioned(
            left: 4 * 24.0,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Text(
                '+',
                style: TextStyle(color: MarketingColors.primary, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DashboardMockup(),
              Container(
                height: 12,
                width: 520,
                margin: const EdgeInsets.only(left: 40),
                decoration: const BoxDecoration(
                  color: Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                ),
              ),
            ],
          ),
          const Positioned(
            right: 8,
            bottom: 0,
            child: PhoneMockup(
              child: PhoneAppContent(
                greeting: 'Good Morning,\nSarah! 👋',
                subtitle: "Let's make today amazing.",
                quickActions: [('✓', 'Attendance'), ('¤', 'Homework'), ('✓', 'Fees'), ('🚌', 'Transport')],
                footerTitle: "Today's Classes",
                footerBody: 'Grade 6A · Mathematics\nGrade 8B · Mathematics',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  static const _stats = [
    ('500+', 'Schools (Target)'),
    ('Global', 'Reach'),
    ('1M+', 'Students (Target)'),
    ('Secure', '& Reliable'),
    ('Better', 'Tomorrow'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: MarketingColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < MarketingBreakpoints.tablet ? 2 : 5;
          return Wrap(
            children: [
              for (var i = 0; i < _stats.length; i++)
                SizedBox(
                  width: constraints.maxWidth / columns,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: columns == 5 && i != _stats.length - 1
                        ? const BoxDecoration(
                            border: Border(right: BorderSide(color: MarketingColors.border)),
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stats[i].$1,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: MarketingColors.text,
                          ),
                        ),
                        Text(_stats[i].$2, style: const TextStyle(fontSize: 12, color: MarketingColors.subtle)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
