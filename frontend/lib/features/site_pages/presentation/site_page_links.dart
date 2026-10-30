import 'package:url_launcher/url_launcher.dart';

/// A page's address as somebody would type it: school365ai.com/terms. The
/// web root serves that plain address from the page's own HTML file (docs/seo.md).
String publicAddress(String slug) => '${Uri.base.host}/$slug';

/// Opens the published page in a new tab, so the editor stays where it was.
///
/// Where the app runs at /app/ - production since docs/seo.md S2 - that is
/// the plain-HTML page visitors and search engines read. Anywhere else (a
/// development server, with no public pages beside it) it is the app's own
/// rendering of the page.
Future<void> openPublishedPage(String slug) {
  final address = Uri.base.path.startsWith('/app/') ? '${Uri.base.origin}/$slug' : '${Uri.base.origin}/#/pages/$slug';

  return launchUrl(Uri.parse(address), webOnlyWindowName: '_blank');
}
