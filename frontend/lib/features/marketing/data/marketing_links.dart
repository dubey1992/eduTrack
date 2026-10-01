/// Where a footer line points, and what happens when somebody clicks it
/// (docs/marketing-content.md, slice 5).
///
/// The server decides what may be stored; this decides what to do with
/// what came back. The two lists have to agree, and a test on each side
/// keeps them honest - but the server is the gate. Anything that reaches
/// here has already been through it, and this refuses again anyway,
/// because a page on the open web should not be one bug away from
/// following an address nobody checked.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// What to do with an address.
enum MarketingLinkKind {
  /// Somewhere else on the web - opened in a new tab, so the homepage is
  /// not lost behind it.
  web,

  /// A page of this app, such as `/login`.
  inApp,

  /// An address the device handles: `mailto:` or `tel:`.
  handoff,
}

/// How [url] should be opened, or null if it is not an address this page
/// will follow. A line whose address reads as null stays plain text.
MarketingLinkKind? linkKind(String? url) {
  if (url == null) return null;

  final address = url.trim();

  if (address.startsWith('https://') || address.startsWith('http://')) {
    return address.split('://')[1].isEmpty ? null : MarketingLinkKind.web;
  }

  if (address.startsWith('mailto:') || address.startsWith('tel:')) {
    return address.split(':')[1].isEmpty ? null : MarketingLinkKind.handoff;
  }

  // A page of this site. Checked for a space because a path with one is
  // nearly always a mistyped address rather than a route.
  if (address.startsWith('/')) return address.contains(' ') ? null : MarketingLinkKind.inApp;

  return null;
}

/// Follows [url] the way its kind says to. Does nothing at all for an
/// address this page will not follow.
Future<void> followMarketingLink(BuildContext context, String? url) async {
  final kind = linkKind(url);

  if (kind == null) return;

  final address = url!.trim();

  switch (kind) {
    case MarketingLinkKind.inApp:
      context.go(address);
    case MarketingLinkKind.web:
      // A new tab: a visitor reading about the product should not lose
      // the page they were reading to look at a privacy policy.
      await launchUrl(Uri.parse(address), webOnlyWindowName: '_blank');
    case MarketingLinkKind.handoff:
      await launchUrl(Uri.parse(address));
  }
}
