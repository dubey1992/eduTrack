import 'package:flutter/material.dart';

import '../marketing_colors.dart';
import 'early_access_form.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';

class CtaSection extends StatelessWidget {
  const CtaSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [MarketingColors.primary, MarketingColors.primaryDark]),
      ),
      child: MarketingWrap(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < MarketingBreakpoints.tablet;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Be Part of the Future of Education',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 6),
                Text(
                  "We're currently inviting schools worldwide to join our early access program.\n"
                  'Get exclusive access, provide feedback, and help shape the future of School365ai.',
                  style: TextStyle(color: Color(0xFFDBEAFE), fontSize: 14),
                ),
              ],
            );
            final button = MarketingPrimaryButton(
              label: 'Join Early Access →',
              onPressed: () => showEarlyAccessDialog(context),
              background: Colors.white,
              foreground: MarketingColors.primary,
              glow: false,
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 20), button],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 20),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}
