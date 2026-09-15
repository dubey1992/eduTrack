import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'marketing_colors.dart';
import 'widgets/cta_section.dart';
import 'widgets/features_section.dart';
import 'widgets/early_access_form.dart';
import 'widgets/hero_section.dart';
import 'widgets/marketing_footer.dart';
import 'widgets/marketing_nav_bar.dart';
import 'widgets/mobile_app_section.dart';
import 'widgets/web_app_section.dart';

/// The public marketing homepage (route '/', reachable without a session) -
/// a Flutter recreation of docs/marketing/edusync_marketing_page_prototype.html,
/// rebranded to School365ai. Visitors reach the actual app via the nav bar's
/// "Login" button; there is no session/auth involved on this screen itself.
class MarketingScreen extends StatefulWidget {
  const MarketingScreen({super.key});

  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  final _scrollController = ScrollController();
  final _homeKey = GlobalKey();
  final _featuresKey = GlobalKey();
  final _schoolsKey = GlobalKey();
  final _mobileKey = GlobalKey();
  final _aboutKey = GlobalKey();
  final _contactKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarketingColors.background,
      // The prototype specifies `font-family: Inter, ...` - the rest of the
      // app deliberately has no font opinion (falls back to Flutter's
      // default, Roboto), so this is scoped to just this page rather than
      // the shared AppTheme. TextStyle.merge only fills in fields the
      // per-widget style left unset, so every explicit color/weight/size
      // already authored below is untouched - only fontFamily is added.
      body: DefaultTextStyle.merge(
        style: GoogleFonts.poppins(),
        child: Column(
          children: [
            MarketingNavBar(
              onNavigate: {
                'Home': () => _scrollTo(_homeKey),
                'Features': () => _scrollTo(_featuresKey),
                'For Schools': () => _scrollTo(_schoolsKey),
                'Mobile App': () => _scrollTo(_mobileKey),
                'About': () => _scrollTo(_aboutKey),
                'Contact': () => _scrollTo(_contactKey),
              },
              onJoinEarlyAccess: () => showEarlyAccessDialog(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    KeyedSubtree(key: _homeKey, child: const HeroSection()),
                    KeyedSubtree(key: _featuresKey, child: const FeaturesSection()),
                    KeyedSubtree(key: _mobileKey, child: const MobileAppSection()),
                    KeyedSubtree(key: _schoolsKey, child: const WebAppSection()),
                    KeyedSubtree(key: _aboutKey, child: const CtaSection()),
                    KeyedSubtree(key: _contactKey, child: const MarketingFooter()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
