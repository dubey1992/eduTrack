import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketing_content_repository.dart';
import '../marketing_colors.dart';
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
            final button = MarketingPrimaryButton(
              label: words.text('cta.button'),
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
