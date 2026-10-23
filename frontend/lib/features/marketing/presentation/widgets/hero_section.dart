import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketing_content_repository.dart';

import '../marketing_colors.dart';
import 'dashboard_mockup.dart';
import 'early_access_form.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';
import 'phone_mockup.dart';

class HeroSection extends ConsumerWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _HeroCopy extends ConsumerWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(marketingContentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarketingEyebrow(text: words.text('hero.eyebrow')),
        const SizedBox(height: 16),
        Text(
          words.text('hero.headline'),
          style: const TextStyle(
            fontSize: 46,
            height: 1.05,
            letterSpacing: -1.5,
            fontWeight: FontWeight.w800,
            color: MarketingColors.text,
          ),
        ),
        const SizedBox(height: 12),
        Text(words.text('hero.body'), style: const TextStyle(fontSize: 17, color: Color(0xFF334155), height: 1.4)),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MarketingPrimaryButton(
              label: words.text('hero.primaryButton'),
              onPressed: () => showEarlyAccessDialog(context),
            ),
            MarketingOutlineButton(
              label: words.text('hero.secondaryButton'),
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
              child: Text(words.text('hero.trustLine'), style: TextStyle(fontSize: 13, color: MarketingColors.subtle)),
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

  /// The size the illustration is drawn at. Everything inside is laid out
  /// against it - the mock-up's 590, the laptop base's 520, the phone's
  /// offset from the right edge - so it is a composition, not a layout.
  static const _design = Size(590, 400);

  @override
  Widget build(BuildContext context) {
    // Scaled to fit rather than laid out to fit. At phone width the pieces
    // cannot be made to agree - the mock-up alone is 590 wide, and on a
    // 390-wide screen it overflowed by 202 pixels, with two more overflows
    // inside it - and the honest answer for a decorative picture is to draw
    // it smaller rather than rearrange a thing that is pretending to be a
    // screenshot. scaleDown, so it is never blown up past its design size
    // on a desktop.
    // Kept out of the focus order and out of the semantics tree, because it
    // is a picture of a product, not the product: a keyboard user tabbing
    // the page should not stop on a fake dashboard, and a screen reader
    // should not read one out.
    //
    // It also settles a console error. Every Text inside a SelectionArea is
    // focusable, so this illustration enrolled its whole contents in focus
    // traversal - and when the browser view takes focus, Flutter sorts
    // every focusable node into reading order, asking each for its rect.
    // A Stack in here had not been laid out yet, and an unlaid-out RenderBox
    // has no size to give: "RenderBox was not laid out: RenderStack".
    return ExcludeFocus(
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: _design.width,
            height: _design.height,
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
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(marketingContentProvider).list('hero.stats');

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
              for (var i = 0; i < stats.length; i++)
                SizedBox(
                  width: constraints.maxWidth / columns,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: columns == 5 && i != stats.length - 1
                        ? const BoxDecoration(
                            border: Border(right: BorderSide(color: MarketingColors.border)),
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stats[i]['value'] ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: MarketingColors.text,
                          ),
                        ),
                        Text(
                          stats[i]['label'] ?? '',
                          style: const TextStyle(fontSize: 12, color: MarketingColors.subtle),
                        ),
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
