import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../marketing_colors.dart';
import 'marketing_wrap.dart';

class MarketingFooter extends StatefulWidget {
  const MarketingFooter({super.key});

  @override
  State<MarketingFooter> createState() => _MarketingFooterState();
}

class _MarketingFooterState extends State<MarketingFooter> {
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
        title: Text("You're on the list", style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          "We'll send the latest School365ai news and updates to this address.",
          style: GoogleFonts.inter(),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: MarketingColors.primary),
            child: Text('Got it', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    _emailController.clear();
  }

  @override
  Widget build(BuildContext context) {
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
                  const _LinkColumn(title: 'Product', links: ['Features', 'Web Dashboard', 'Mobile App', 'Pricing']),
                  const _LinkColumn(title: 'Company', links: ['About Us', 'Careers', 'Blog', 'Contact']),
                  const _LinkColumn(title: 'Resources', links: ['Help Center', 'Privacy Policy', 'Terms', 'Security']),
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
            const Row(
              children: [
                Expanded(
                  child: Text(
                    '© 2026 School365ai. All rights reserved.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Smarter Schools. Brighter Futures.',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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

class _BrandColumn extends StatelessWidget {
  const _BrandColumn();

  @override
  Widget build(BuildContext context) {
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
            const Text(
              'School365ai',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: MarketingColors.text),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Modern school management for smarter schools and brighter futures.',
          style: TextStyle(color: MarketingColors.subtle, fontSize: 13),
        ),
      ],
    );
  }
}

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({required this.title, required this.links});

  final String title;
  final List<String> links;

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
            child: Text(link, style: const TextStyle(color: MarketingColors.subtle, fontSize: 13)),
          ),
      ],
    );
  }
}

class _NewsletterColumn extends StatelessWidget {
  const _NewsletterColumn({required this.emailController, required this.onSubscribe});

  final TextEditingController emailController;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Stay Updated',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MarketingColors.text),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Text(
            'Get the latest news and updates.',
            style: TextStyle(color: MarketingColors.subtle, fontSize: 13),
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
