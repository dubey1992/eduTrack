import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The ways off the sign-in page to the public website (asked for
/// 2026-11-06): the logo goes home, a new school can book a demo, and
/// anyone stuck can message School365ai on WhatsApp.
///
/// The website and the app share one domain - the app lives under /app/ -
/// so the website's addresses are worked out from wherever the app was
/// opened, and a local copy points at its own server.
class WebsiteLinks {
  const WebsiteLinks._();

  /// School365ai's support number, the same one the website shows
  /// (backend-python/school/site_pages.py SUPPORT_PHONE): change both
  /// together.
  static const supportPhone = '+91-9205313831';

  static Uri get home => Uri.base.resolve('/');

  /// The website's homepage with its demo form open.
  static Uri get bookDemo => Uri.base.resolve('/#request-a-demo');

  static final whatsApp = Uri.parse(
    'https://wa.me/919205313831?text=${Uri.encodeComponent('Hello School365ai team, I need help signing in.')}',
  );

  /// Opens [address]: the website in this tab, WhatsApp beside it.
  static Future<void> open(Uri address) => opener(address);

  /// What [open] does; a test swaps it to see where a link would go.
  @visibleForTesting
  static Future<void> Function(Uri address) opener = _launch;

  static Future<void> _launch(Uri address) async {
    await launchUrl(
      address,
      webOnlyWindowName: address.host == Uri.base.host ? '_self' : '_blank',
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }
}
