import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../marketing_colors.dart';
import 'marketing_buttons.dart';
import 'marketing_wrap.dart';

/// The sticky top nav, matching the prototype's `.nav` - brand mark, anchor
/// links to each section (hidden below [MarketingBreakpoints.tablet], same
/// as the source `.links{display:none}` rule), and Login/Join Early Access
/// actions.
///
/// The bar is the first thing anyone sees, on whatever device they own, so it
/// is built so it cannot run off the edge: the brand and the actions are
/// fixed, and everything between them lives in the space that is left.
class MarketingNavBar extends StatelessWidget {
  const MarketingNavBar({super.key, required this.onNavigate, required this.onJoinEarlyAccess});

  /// label -> scroll callback, in display order.
  final Map<String, VoidCallback> onNavigate;
  final VoidCallback onJoinEarlyAccess;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MarketingColors.border)),
      ),
      child: MarketingWrap(
        // What fits in this bar is worked out by measuring text, so it has to
        // be worked out again when the text changes shape. The page's font
        // arrives over the network: until it does, everything is measured in
        // a fallback, and when it lands Flutter relays out the paragraphs but
        // does not rebuild the builders below that sized the boxes around
        // them. Without this the tagline spent a first visit ellipsised
        // inside a box built to fit it, and only a window resize put it
        // right.
        child: ListenableBuilder(
          listenable: PaintingBinding.instance.systemFonts,
          builder: (context, _) => _bar(context),
        ),
      ),
    );
  }

  /// Measured from the space this bar actually has, not from the window.
  /// MarketingWrap caps and pads its content, so the window can be wide while
  /// the row inside is not - reading the window made the bar keep links it had
  /// nowhere to put.
  Widget _bar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < MarketingBreakpoints.tablet;
        // On a phone the brand and both actions at full width already
        // exceed the screen, so the call to action shortens rather than
        // the bar spilling over the edge.
        final isTight = constraints.maxWidth < 480;

        return Row(
          children: [
            if (isCompact) ...[
              // There are no links to protect on a phone, so the brand
              // simply gives way: loose, so it shrinks rather than
              // pushing the row over the edge.
              const Flexible(child: _Brand()),
              // Nothing sits between the brand and the actions here, and
              // the brand takes every pixel it is offered - so without
              // this the tagline ends up against the Login border.
              const SizedBox(width: _linksTrailingGap),
            ] else
              // Sized to what the brand actually needs, so that
              // everything after it is genuinely what is left over.
              // Sharing the row out by flex looked tidier but cannot
              // work: a loose Flexible that uses less than its share does
              // not hand the rest back, so the brand sat on a third of
              // half the bar while the links were squeezed into what
              // remained and the first one came out cut down the middle.
              SizedBox(
                // Never past half the bar, whatever font it ends up drawn
                // in: a brand that eats the row is worse than one that
                // ellipsises.
                width: math.min(_brandWidth(context), constraints.maxWidth / 2),
                child: const _Brand(),
              ),
            // The links take whatever the brand and the actions leave,
            // and show only if all of them fit in it. They used to scroll
            // inside that space instead, which meant the first one
            // arrived cut down the middle: that reads as a broken page
            // rather than as something to scroll, and every section is
            // still reachable by scrolling the page itself.
            // Left out of the row entirely when there is no room, not
            // merely emptied: an Expanded with nothing in it still
            // reserves its share of the bar, which is what used to
            // squeeze the brand on a phone.
            if (!isCompact)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, forLinks) {
                    final gap = _linkGapWithin(context, forLinks.maxWidth, onNavigate.keys);
                    if (gap == null) return const SizedBox.shrink();

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final entry in onNavigate.entries)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: gap),
                            child: InkWell(
                              onTap: entry.value,
                              child: Text(entry.key, style: _linkStyle),
                            ),
                          ),
                        const SizedBox(width: _linksTrailingGap),
                      ],
                    );
                  },
                ),
              ),
            MarketingOutlineButton(label: 'Login', onPressed: () => context.go('/login')),
            const SizedBox(width: 10),
            MarketingPrimaryButton(label: isTight ? 'Join' : 'Join Early Access', onPressed: onJoinEarlyAccess),
          ],
        );
      },
    );
  }
}

const _linkStyle = TextStyle(fontSize: 14, color: Color(0xFF334155));
const _wordmark = 'School365ai';
const _wordmarkStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 20, height: 1.1, color: MarketingColors.text);
const _tagline = 'Smarter Schools. Brighter Futures.';
const _taglineStyle = TextStyle(fontSize: 11, height: 1.3, color: MarketingColors.subtle);
const _logoSize = 38.0;
const _logoGap = 10.0;
const _linkGap = 13.0;
const _minLinkGap = 8.0;
const _linksTrailingGap = 16.0;

/// The space to put either side of each link, or null if the whole set cannot
/// be shown in [available] at all.
///
/// The gap is the first thing to give: the links themselves are the point of
/// the bar, so they are spaced as generously as the room allows and tighten
/// before any of them is dropped. Below [_minLinkGap] they stop reading as
/// separate links and are better gone altogether.
///
/// Measured against the font actually in use, because a constant would have
/// to be wrong somewhere - the same labels are a different width in Poppins
/// than in the test suite's font, so a number tuned for one hides the links
/// on a bar that had room, or clips them on one that did not.
double? _linkGapWithin(BuildContext context, double available, Iterable<String> labels) {
  var text = _linksTrailingGap;
  for (final label in labels) {
    text += _textWidth(context, label, _linkStyle);
  }

  final gap = (available - text) / (labels.length * 2);

  return gap < _minLinkGap ? null : math.min(gap, _linkGap);
}

/// How much room the brand needs to be drawn whole.
///
/// Rounded up rather than handed back to the pixel, because this number comes
/// straight back as the width the text is then laid out in: measured exactly,
/// the tagline lands a hair over its own measurement and ellipsises inside a
/// box built specifically to fit it.
double _brandWidth(BuildContext context) {
  final text = math.max(_textWidth(context, _wordmark, _wordmarkStyle), _textWidth(context, _tagline, _taglineStyle));

  return _logoSize + _logoGap + text.ceilToDouble() + 1;
}

/// How wide [text] will actually come out.
///
/// Resolved against the context rather than measured from the bare style: the
/// marketing page sets its font through a DefaultTextStyle and the constants
/// above carry only size and colour. Measuring without the inherited font
/// gives a narrower answer than the browser draws - which is how the tagline
/// came to be cut with no ellipsis to show for it.
double _textWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();

  final width = painter.width;
  painter.dispose();

  return width;
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _logoSize,
          height: _logoSize,
          decoration: BoxDecoration(color: MarketingColors.primary, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: const Text('🎓', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: _logoGap),
        // mainAxisSize.min matters here: without it this Column stretches to
        // match the Row's full height (driven by the buttons on the other
        // end) and, with the default mainAxisAlignment.start, pins both lines
        // to the top of that taller box - reading as "text sits above the
        // logo's center" instead of actually being centered against it.
        // Flexible so the wordmark can ellipsize rather than push the row
        // wider than the space the bar gave it.
        Flexible(
          child: LayoutBuilder(
            builder: (context, forWordmark) {
              // The tagline is decorative and, at 11px, naturally wider than
              // the name above it - so it is the first thing to give way. It
              // goes whole rather than ellipsised: "Brighter Futu..." is not a
              // tagline, it is a mistake.
              final showsTagline = forWordmark.maxWidth >= _textWidth(context, _tagline, _taglineStyle);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The name itself always shows, ellipsised if it must be:
                  // a bar with no brand on it is worse than a shortened one.
                  const Text(_wordmark, maxLines: 1, overflow: TextOverflow.ellipsis, style: _wordmarkStyle),
                  if (showsTagline)
                    // The ellipsis is a safety net, not the plan: the
                    // measurement above is what decides, but the page's font
                    // arrives over the network and the first layout can be
                    // measured against a fallback. Better a "..." for one
                    // frame than a sentence silently cut.
                    const Text(_tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: _taglineStyle),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
