import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/brand_tokens.dart';
import '../../../../core/widgets/school365_mark.dart';
import 'website_links.dart';

/// The left half of the desktop sign-in page (School365AI design,
/// 2026-11-21, after the website's dark sections): the deep navy panel with the
/// name, one sentence about the product, and who signs in where. Only shown
/// on wide screens - [LoginScreen] keeps a phone to the form and [BrandMark].
class LoginStoryPanel extends StatelessWidget {
  const LoginStoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: const Key('login-story'),
      color: dark ? const Color(0xFF071427) : BrandColors.deep,
      child: Stack(
        children: [
          // Two soft circles, teal at the top right and orange at the bottom
          // left, as on the website. Decoration only.
          const Positioned(top: -240, right: -245, child: _Glow(size: 540, colour: Color(0x40087E79))),
          const Positioned(bottom: -240, left: -130, child: _Glow(size: 380, colour: Color(0x22FFB76A))),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final roomy = constraints.maxHeight > 760;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth > 640 ? 64 : 40, vertical: 40),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const BrandMark(showTagline: true, onDark: true),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: roomy ? 40 : 28),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SCHOOL MANAGEMENT, ALL IN ONE PLACE',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    color: const Color(0xFF8EDBCE),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const _Headline(),
                                const SizedBox(height: 18),
                                Text(
                                  'Attendance, timetables, fees, the school bus and messages to parents, '
                                  'for everyone who works at the school.',
                                  style: GoogleFonts.dmSans(fontSize: 16, height: 1.55, color: const Color(0xFFC2D7E1)),
                                ),
                                SizedBox(height: roomy ? 32 : 24),
                                const _WhoSignsIn(),
                              ],
                            ),
                          ),
                        ),
                        Text('© School365ai', style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF9FB3C4))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Every school day, a little simpler." - the last word in teal, as the
/// website sets its headlines.
class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final style = GoogleFonts.manrope(
      fontSize: width > 1400 ? 54 : 42,
      height: 1.08,
      letterSpacing: -1.6,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Every school day,\na little '),
          TextSpan(
            text: 'simpler.',
            style: style.copyWith(color: BrandColors.nightTeal),
          ),
        ],
      ),
      key: const Key('login-headline'),
      style: style,
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.colour});

  final double size;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
      ),
    );
  }
}

/// The School365ai mark and name, which take you to the website's homepage.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.showTagline = false, this.onDark = false});

  final bool showTagline;

  /// On the navy panel rather than the off-white page.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Go to the School365ai website',
      child: InkWell(
        key: const Key('login-logo'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => WebsiteLinks.open(WebsiteLinks.home),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: School365Wordmark(
            markSize: 42,
            fontSize: 21,
            onDark: onDark,
            tagline: showTagline ? 'Smarter Schools. Brighter Futures.' : null,
          ),
        ),
      ),
    );
  }
}

/// Which way in is whose: the question people get wrong most often here.
class _WhoSignsIn extends StatelessWidget {
  const _WhoSignsIn();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('who-signs-in'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        border: Border.all(color: const Color(0x2EFFFFFF)),
        borderRadius: BorderRadius.circular(BrandRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Who signs in here?',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const _WhoRow(
            icon: Icons.badge_outlined,
            title: 'School staff',
            detail:
                'Admins, teachers, accountants and office staff: the email and password your school set up for you.',
          ),
          const _WhoRow(
            icon: Icons.directions_bus_outlined,
            title: 'Bus crew',
            detail:
                'Drivers and attendants: your mobile number and passcode, not an email. Use the button under the form.',
          ),
          const _WhoRow(
            icon: Icons.family_restroom_outlined,
            title: 'Parents',
            // The Family app is built but not yet on Google Play (2026-11-17).
            detail:
                'The School365ai Family app is coming soon. Until then, your school sends attendance, bus and '
                'fee updates to your phone.',
          ),
        ],
      ),
    );
  }
}

class _WhoRow extends StatelessWidget {
  const _WhoRow({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: const Color(0xFF8EDBCE)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  TextSpan(text: detail),
                ],
              ),
              style: GoogleFonts.dmSans(fontSize: 14, height: 1.45, color: const Color(0xFFC2D7E1)),
            ),
          ),
        ],
      ),
    );
  }
}
