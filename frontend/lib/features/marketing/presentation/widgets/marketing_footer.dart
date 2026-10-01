import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketing_content_repository.dart';
import '../../data/marketing_links.dart';

import 'package:google_fonts/google_fonts.dart';

import '../marketing_colors.dart';
import 'marketing_wrap.dart';
import '../../../../core/widgets/dialog_message.dart';

class MarketingFooter extends ConsumerStatefulWidget {
  const MarketingFooter({super.key});

  @override
  ConsumerState<MarketingFooter> createState() => _MarketingFooterState();
}

class _MarketingFooterState extends ConsumerState<MarketingFooter> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    if (_emailController.text.trim().isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("You're on the list", style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        content: DialogMessage(
          "We'll send the latest School365ai news and updates to this address.",
          style: GoogleFonts.poppins(),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: MarketingColors.primary),
            child: Text('Got it', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    _emailController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(marketingContentProvider);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: MarketingWrap(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < MarketingBreakpoints.tablet ? 2 : 5;
                final items = [
                  const _BrandColumn(),
                  // Three columns, not a variable number: the row is the
                  // brand, these, and the newsletter across five.
                  _LinkColumn(title: words.text('footer.productTitle'), links: words.list('footer.productLinks')),
                  _LinkColumn(title: words.text('footer.companyTitle'), links: words.list('footer.companyLinks')),
                  _LinkColumn(title: words.text('footer.resourceTitle'), links: words.list('footer.resourceLinks')),
                  _NewsletterColumn(emailController: _emailController, onSubscribe: _subscribe),
                ];
                return Wrap(
                  spacing: 28,
                  runSpacing: 28,
                  children: [
                    for (final item in items)
                      SizedBox(width: (constraints.maxWidth - 28 * (columns - 1)) / columns, child: item),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            const Divider(color: MarketingColors.border, height: 1),
            const SizedBox(height: 15),
            // Wrap.alignment only spaces out multiple *runs* (wrapped
            // lines), so with these two short texts (which always fit on
            // one run) it had nothing to distribute and they sat jammed
            // together at the left instead of spreading to opposite ends.
            // A Row with spaceBetween does spread them - but a bare Row has
            // no flex, so at 12px it can hard-overflow rather than just
            // look cramped once the viewport gets narrow (this bit a test
            // at ~760px). Expanded on each side guarantees it never can,
            // while still spreading apart exactly like spaceBetween would
            // whenever there's room.
            Row(
              children: [
                Expanded(
                  child: Text(
                    words.text('footer.copyright'),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    words.text('footer.tagline'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandColumn extends ConsumerWidget {
  const _BrandColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(marketingContentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: MarketingColors.primary, borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: const Text('🎓', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            // Trims rather than spilling: this column is one of several in a
            // footer that narrows with the viewport.
            Flexible(
              child: Text(
                words.text('footer.wordmark'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: MarketingColors.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(words.text('footer.blurb'), style: const TextStyle(color: MarketingColors.subtle, fontSize: 13)),
      ],
    );
  }
}

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({required this.title, required this.links});

  final String title;
  final List<Map<String, String>> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        for (final link in links)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: _FooterLink(label: link['label'] ?? '', url: link['url']),
          ),
      ],
    );
  }
}

/// One line in a footer column.
///
/// With an address it behaves like a link - a pointer, an underline under
/// the cursor, and a tap that goes somewhere. Without one it is the plain
/// text the whole column used to be, which is what every line ships as.
class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.label, required this.url});

  final String label;
  final String? url;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: MarketingColors.subtle, fontSize: 13);

    if (linkKind(widget.url) == null) return Text(widget.label, style: style);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => followMarketingLink(context, widget.url),
        child: Semantics(
          link: true,
          child: Text(widget.label, style: style.copyWith(decoration: _hovered ? TextDecoration.underline : null)),
        ),
      ),
    );
  }
}

class _NewsletterColumn extends ConsumerWidget {
  const _NewsletterColumn({required this.emailController, required this.onSubscribe});

  final TextEditingController emailController;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(marketingContentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          words.text('footer.newsletterTitle'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(
            words.text('footer.newsletterBody'),
            style: const TextStyle(color: MarketingColors.subtle, fontSize: 13),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(8),
          ),
          // Neither the TextField's white fill nor the submit button's blue
          // fill know about the container's rounded corners - as plain
          // rectangles they paint square corners straight over the border's
          // curve. ClipRRect (radius shrunk by the 1px border so it nests
          // just inside the border stroke rather than cutting into it) is
          // what actually makes the pair look like one rounded pill.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            // A filled TextField blends the ambient Theme's hoverColor over
            // its fillColor on mouseover (and again on focus) regardless of
            // the fillColor/border values set below - visible here as the
            // white fill turning grey just from resting the pointer over the
            // field, before any click. Same theme-leakage pattern as the
            // border fix above, so it gets the same local-Theme-override
            // treatment: force both overlays transparent for this field.
            child: Row(
              children: [
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(hoverColor: Colors.transparent, focusColor: Colors.transparent),
                    child: TextField(
                      controller: emailController,
                      // This page hardcodes its own light palette everywhere
                      // else (it never reads Theme.of(context) for color),
                      // but a bare TextField still falls back to the app's
                      // ambient Theme.inputDecorationTheme for anything it
                      // doesn't set itself - on a system in dark mode that
                      // meant a near-black fill with near-white hint text
                      // here. Setting fillColor/hintStyle/style explicitly
                      // keeps this field matching the rest of the page
                      // regardless of the visitor's OS theme.
                      style: const TextStyle(fontSize: 13, color: MarketingColors.text),
                      decoration: const InputDecoration(
                        hintText: 'Enter your email',
                        hintStyle: TextStyle(fontSize: 13, color: MarketingColors.subtle),
                        filled: true,
                        fillColor: Colors.white,
                        // `border` alone only covers the default/error
                        // states - the ambient AppTheme's
                        // inputDecorationTheme still supplies its own
                        // focusedBorder (a black outline) once this field
                        // gains focus, the same kind of theme-leakage that
                        // caused the earlier dark-mode fill bug. Every
                        // border state has to be silenced explicitly for
                        // this hardcoded-palette page.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 9),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: onSubscribe,
                  child: Container(
                    width: 42,
                    height: 38,
                    color: MarketingColors.primary,
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
