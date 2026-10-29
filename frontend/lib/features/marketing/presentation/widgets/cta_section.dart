import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketing_content_repository.dart';
import '../marketing_colors.dart';
import 'demo_request_form.dart';
import 'early_access_form.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';

class CtaSection extends ConsumerWidget {
  const CtaSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(marketingContentProvider);

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
              children: [
                Text(
                  words.text('cta.headline'),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(words.text('cta.body'), style: const TextStyle(color: Color(0xFFDBEAFE), fontSize: 14)),
              ],
            );
            final button = Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MarketingPrimaryButton(
                  label: words.text('cta.button'),
                  onPressed: () => showEarlyAccessDialog(context),
                  background: Colors.white,
                  foreground: MarketingColors.primary,
                  glow: false,
                ),
                // The second way in, quieter on the blue: a translucent
                // white rather than a second solid one.
                MarketingPrimaryButton(
                  label: words.text('cta.demoButton'),
                  onPressed: () => showDemoRequestDialog(context),
                  background: const Color(0x33FFFFFF),
                  foreground: Colors.white,
                  glow: false,
                ),
              ],
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
