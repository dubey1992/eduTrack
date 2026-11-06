import 'package:flutter/material.dart';

import 'auth_palette.dart';
import 'website_links.dart';

/// The top of the desktop sign-in page (redesigned 2026-11-06): the logo
/// back to the website and what School365ai is in one line. Only shown on
/// wide screens - [LoginScreen] keeps a phone to the form and [BrandMark].
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1300;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(showTagline: true),
            SizedBox(height: isCompact ? 24 : 32),
            Text(
              'SCHOOL MANAGEMENT, ALL IN ONE PLACE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: palette.primary),
            ),
            const SizedBox(height: 10),
            Text(
              'Run your whole school day from one sign-in.',
              style: TextStyle(
                fontSize: isCompact ? 36 : 46,
                height: 1.12,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Attendance, timetables, fees, the school bus and messages to parents, '
              'for everyone who works at the school.',
              style: TextStyle(fontSize: 17, color: palette.muted, height: 1.45),
            ),
          ],
        );
      },
    );
  }
}

/// Beside the form: who signs in where, over a real school photograph.
class BrandDetails extends StatelessWidget {
  const BrandDetails({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WhoSignsIn(),
        SizedBox(height: 20),
        Expanded(child: _SchoolPhoto()),
      ],
    );
  }
}

/// The School365ai logo, which takes you to the website's homepage.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.showTagline = false});

  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return Tooltip(
      message: 'Go to the School365ai website',
      child: InkWell(
        key: const Key('login-logo'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => WebsiteLinks.open(WebsiteLinks.home),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.school, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'School365ai',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: palette.text),
                  ),
                  if (showTagline)
                    Text('Smarter Schools. Brighter Futures.', style: TextStyle(fontSize: 13, color: palette.subtle)),
                ],
              ),
            ],
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
    final palette = AuthPalette.of(context);

    return Container(
      key: const Key('who-signs-in'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Who signs in here?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.text),
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
            title: 'Bus attendants',
            detail: 'Your mobile number and passcode, not an email: use the button under the form.',
          ),
          const _WhoRow(
            icon: Icons.family_restroom_outlined,
            title: 'Parents',
            detail: 'No sign-in needed. Your school sends attendance, bus and fee updates to your phone.',
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
    final palette = AuthPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: palette.primaryLight, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: palette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: TextStyle(fontWeight: FontWeight.w700, color: palette.text),
                  ),
                  TextSpan(text: detail),
                ],
              ),
              style: TextStyle(fontSize: 14, height: 1.45, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A real classroom rather than a picture of the software (asked for
/// 2026-11-06): a student at the blackboard in Bengaluru. Photo by Nikhita S
/// on Unsplash, free to use under the Unsplash License.
class _SchoolPhoto extends StatelessWidget {
  const _SchoolPhoto();

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    // A background, not an Image: it fills the room the form leaves beside
    // it and never decides the row's height itself.
    return Semantics(
      image: true,
      label: 'A student in school uniform writing on a classroom blackboard',
      child: Container(
        key: const Key('login-photo'),
        constraints: const BoxConstraints(minHeight: 220),
        decoration: BoxDecoration(
          color: palette.primaryLight,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 8))],
          image: const DecorationImage(
            image: AssetImage('assets/images/login-classroom.jpg'),
            fit: BoxFit.cover,
            alignment: Alignment(0.3, -0.1),
          ),
        ),
        // What the app does in that classroom's day, over the blackboard
        // (asked for 2026-11-06: the photo alone did not say). Positioned
        // only, so the photo still never sets the row's height; whatever does
        // not fit a short photo is clipped by its rounded corners.
        child: const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          child: Stack(
            children: [
              Positioned(
                left: 20,
                top: 20,
                child: Column(
                  key: Key('login-photo-moments'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AppMoment(
                      icon: Icons.fact_check_outlined,
                      colour: Color(0xFF16A34A),
                      title: 'Attendance marked',
                      detail: 'Class 7 A · 38 of 40 present',
                    ),
                    SizedBox(height: 10),
                    _AppMoment(
                      icon: Icons.directions_bus_outlined,
                      colour: Color(0xFFEA580C),
                      title: 'Bus 3 reached school',
                      detail: '8:02 am · parents told on WhatsApp',
                    ),
                    SizedBox(height: 10),
                    _AppMoment(
                      icon: Icons.receipt_long_outlined,
                      colour: Color(0xFF2563EB),
                      title: 'Fee received ₹XXXXX',
                      detail: 'Receipt sent to the parent',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thing the app just did, drawn like the app's own notices.
class _AppMoment extends StatelessWidget {
  const _AppMoment({required this.icon, required this.colour, required this.title, required this.detail});

  final IconData icon;
  final Color colour;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 19, color: colour),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.text),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
