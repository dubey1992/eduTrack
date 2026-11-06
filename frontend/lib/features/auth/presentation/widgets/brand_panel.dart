import 'package:flutter/material.dart';

import 'auth_palette.dart';
import 'website_links.dart';

/// The desktop sign-in page's left half (redesigned 2026-11-06): the logo
/// back to the website, what School365ai is in one line, who signs in
/// where, and a real picture of the app. Only shown on wide screens -
/// [LoginScreen] keeps a phone to the form and [BrandMark].
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key, this.onAttendantSignIn});

  /// Opens the bus attendant's sign-in; null hides that row's button.
  final VoidCallback? onAttendantSignIn;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below ~1400px (a "tablet"-ish width for this two-column layout,
        // since the shared app-wide desktop cutoff is 1100) the type and the
        // picture shrink rather than crowding the form.
        final isCompact = constraints.maxWidth < 1400;

        return Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 24 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(showTagline: true),
              SizedBox(height: isCompact ? 24 : 36),
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
              SizedBox(height: isCompact ? 20 : 28),
              _WhoSignsIn(onAttendantSignIn: onAttendantSignIn),
              SizedBox(height: isCompact ? 20 : 28),
              const _AppPreview(),
            ],
          ),
        );
      },
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
  const _WhoSignsIn({required this.onAttendantSignIn});

  final VoidCallback? onAttendantSignIn;

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
          _WhoRow(
            icon: Icons.directions_bus_outlined,
            title: 'Bus attendants',
            detail: 'Your mobile number and passcode, not an email.',
            action: onAttendantSignIn == null
                ? null
                : TextButton(
                    onPressed: onAttendantSignIn,
                    style: TextButton.styleFrom(foregroundColor: palette.primary),
                    child: const Text('Sign in with mobile'),
                  ),
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
  const _WhoRow({required this.icon, required this.title, required this.detail, this.action});

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

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
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// A real screenshot of the app rather than a drawing of one: what the
/// person is about to sign in to.
class _AppPreview extends StatelessWidget {
  const _AppPreview();

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: AspectRatio(
          aspectRatio: 16 / 6.4,
          child: Image.asset(
            'assets/images/app-preview.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            semanticLabel: "The School365ai app: a school's finished Setup Guide",
            errorBuilder: (context, error, stack) => ColoredBox(color: palette.primaryLight),
          ),
        ),
      ),
    );
  }
}
