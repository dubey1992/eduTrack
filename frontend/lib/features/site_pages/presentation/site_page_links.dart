import 'package:url_launcher/url_launcher.dart';

/// A page's address as somebody would type it: school365ai.com/terms. The
/// web host sends that plain address on to the page (frontend/web/.htaccess).
String publicAddress(String slug) => '${Uri.base.host}/$slug';

/// Opens the published page in a new tab, so the editor stays where it was.
///
/// The app's own route rather than the plain address, so it also works on a
/// development server, which has no .htaccess to send the plain one on.
Future<void> openPublishedPage(String slug) {
  return launchUrl(Uri.parse('${Uri.base.origin}/#/pages/$slug'), webOnlyWindowName: '_blank');
}
