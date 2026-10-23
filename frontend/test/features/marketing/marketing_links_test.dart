import 'package:edutrack_app/features/marketing/data/marketing_defaults.dart';
import 'package:edutrack_app/features/marketing/data/marketing_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a footer line points (docs/marketing-content.md, slice 5).
///
/// The server decides what may be stored; this decides what to do with
/// what came back. The lists have to agree - the same cases are pinned in
/// `test_marketing_content_links_api.py` - and this one refuses again
/// anyway, because a page on the open web should not be one bug away from
/// following an address nobody checked.
void main() {
  group('what kind of address it is', () {
    test('somewhere else on the web opens in a new tab', () {
      for (final url in ['https://example.com', 'http://example.com/terms', 'https://example.com/a?b=c#d']) {
        expect(linkKind(url), MarketingLinkKind.web, reason: url);
      }
    });

    test('a path is a page of this app', () {
      for (final url in ['/login', '/', '/transport/routes']) {
        expect(linkKind(url), MarketingLinkKind.inApp, reason: url);
      }
    });

    test('mail and phone are handed to the device', () {
      expect(linkKind('mailto:hello@example.com'), MarketingLinkKind.handoff);
      expect(linkKind('tel:+15551234567'), MarketingLinkKind.handoff);
    });

    test('script is not an address this page follows', () {
      // The one that matters: the page is served to the open web, and a
      // link whose address is script would run it in a visitor's browser.
      for (final url in [
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'vbscript:msgbox(1)',
      ]) {
        expect(linkKind(url), isNull, reason: url);
      }
    });

    test('a scheme nobody thought about is refused by default', () {
      for (final url in ['ftp://example.com', 'file:///etc/passwd', 'chrome://settings', 'intent://evil']) {
        expect(linkKind(url), isNull, reason: url);
      }
    });

    test('a bare domain is refused, because it is ambiguous', () {
      expect(linkKind('example.com'), isNull);
      expect(linkKind('www.example.com'), isNull);
    });

    test('a scheme with nothing after it is refused', () {
      expect(linkKind('https://'), isNull);
      expect(linkKind('mailto:'), isNull);
    });

    test('a path with a space in it is a mistyped address, not a route', () {
      expect(linkKind('/my page'), isNull);
    });

    test('no address at all is no link', () {
      // Nothing ships this way any more, but a line the Super Admin
      // cleared does, and the whole column was this before slice 5.
      expect(linkKind(null), isNull);
      expect(linkKind(''), isNull);
      expect(linkKind('   '), isNull);
    });

    test('surrounding space does not change what an address is', () {
      expect(linkKind('  https://example.com  '), MarketingLinkKind.web);
    });
  });

  group('the addresses the page ships with', () {
    test('the privacy policy is a page of this site, not a promise of one', () {
      // Play requires a privacy policy that opens, and the footer promised
      // one for months at an address that did not exist
      // (docs/driver-app.md, D6.1).
      final privacy = marketingListDefaults['footer.resourceLinks']!.firstWhere(
        (link) => link['label'] == 'Privacy Policy',
      );

      expect(privacy['url'], '/privacy');
      expect(linkKind(privacy['url']), MarketingLinkKind.inApp);
    });

    test('every footer line carries one this page will follow', () {
      // A line whose address is mistyped silently goes back to being
      // plain text, which looks like nothing at all went wrong.
      for (final key in ['footer.productLinks', 'footer.companyLinks', 'footer.resourceLinks']) {
        for (final link in marketingListDefaults[key]!) {
          expect(linkKind(link['url']), isNotNull, reason: '$key: ${link['label']}');
        }
      }
    });
  });
}
