import 'package:edutrack_app/features/marketing/data/marketing_content.dart';
import 'package:edutrack_app/features/marketing/data/marketing_defaults.dart';
import 'package:edutrack_app/features/marketing/presentation/marketing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/marketing_scope.dart';

Widget wrap({MarketingContent content = const MarketingContent.asItShips(), String location = '/'}) {
  return marketingScope(
    content: content,
    MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => MarketingScreen(section: state.uri.queryParameters['section']),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
        ],
      ),
      // The same Overlay-then-SelectionArea the app is built in
      // (main.dart). It is not decoration here: inside a SelectionArea a
      // Text wraps itself in its own MouseRegion, which is what decides
      // the cursor over a footer line. A test tree without one cannot see
      // that, and said the hand was there while the real page showed an
      // I-beam.
      builder: (context, child) => Overlay(
        initialEntries: [OverlayEntry(builder: (context) => SelectionArea(child: child ?? const SizedBox.shrink()))],
      ),
    ),
  );
}

/// A page whose lists were all replaced - what a visitor sees after the
/// Super Admin has edited them (docs/marketing-content.md, slice 3).
const rewritten = MarketingContent({}, {
  'hero.stats': [
    {'value': '12', 'label': 'Schools signed up'},
  ],
  'features.items': [
    {'icon': '✓', 'title': 'Only One Feature', 'body': 'And that is on purpose'},
  ],
  'web.bullets': [
    {'text': 'The only thing it does'},
  ],
  'footer.productLinks': [
    {'label': 'The only link'},
  ],
});

/// How far the page itself - the vertical scroll that holds every section -
/// is scrolled.
double pageScroll(WidgetTester tester) {
  final page = find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.vertical);

  return tester.widget<SingleChildScrollView>(page.first).controller!.offset;
}

void main() {
  testWidgets('shows the hero headline, feature grid and footer', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Run Your School Smarter, Together.'), findsOneWidget);
    expect(find.text('Powerful Features for Modern Schools'), findsOneWidget);
    expect(find.text('Student Management'), findsOneWidget);
    expect(find.text('Be Part of the Future of Education'), findsOneWidget);
    expect(find.text('© 2026 School365ai. All rights reserved.'), findsOneWidget);
  });

  testWidgets('offers the Android app only, with no App Store badge until there is an iPhone app', (tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('App Store'), findsNothing);
  });

  testWidgets('a plain address for a section opens the page at that section', (tester) async {
    // school365ai.com/contact is redirected by the host to /#/?section=contact.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(location: '/?section=contact'));
    await tester.pumpAndSettle();

    expect(pageScroll(tester), greaterThan(0), reason: 'the footer, where Contact is, is far below the top');
  });

  testWidgets('a section nobody has opens at the top', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(location: '/?section=pricing'));
    await tester.pumpAndSettle();

    expect(pageScroll(tester), 0);
  });

  testWidgets('tapping Login navigates to the login route', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login Screen'), findsOneWidget);
  });

  testWidgets('tapping Request A Demo opens the signup form, not a JS alert', (tester) async {
    // Tall enough for the form; the dialog scrolls, but the fields have to
    // exist to be found.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Request A Demo').first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'School name'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Request access'), findsOneWidget);
  });

  group('the repeating lists', () {
    testWidgets('it draws the lists the server sent, not the ones it ships with', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(content: rewritten));
      await tester.pumpAndSettle();

      expect(find.text('Schools signed up'), findsOneWidget);
      expect(find.text('Only One Feature'), findsOneWidget);
      expect(find.text('The only link'), findsOneWidget);
      // The shipped ones are gone, not drawn underneath.
      expect(find.text('Student Management'), findsNothing);
      expect(find.text('Schools (Target)'), findsNothing);
    });

    testWidgets('more cards than there are colours does not crash the page', (tester) async {
      // The colour list holds ten and the section takes fifteen, so it
      // cycles rather than reaching past its end.
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final many = MarketingContent(const {}, {
        'features.items': [
          for (var i = 1; i <= 15; i++) {'icon': '✓', 'title': 'Card $i', 'body': 'Number $i'},
        ],
      });

      await tester.pumpWidget(wrap(content: many));
      await tester.pumpAndSettle();

      expect(find.text('Card 15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the footer lines', () {
    Future<void> openFooter(WidgetTester tester, MarketingContent content) async {
      tester.view.physicalSize = const Size(1600, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(content: content));
      await tester.pumpAndSettle();
    }

    testWidgets('a line without an address is the plain text it has always been', (tester) async {
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Open Roles'},
          ],
        }),
      );

      expect(find.text('Open Roles'), findsOneWidget);
      expect(find.ancestor(of: find.text('Open Roles'), matching: find.byType(GestureDetector)), findsNothing);
    });

    /// Whether the cursor turns into a hand over [label].
    ///
    /// The *closest* region to the words, not any of them: the one nearest
    /// the pointer is the one that decides, and a page wrapped in a
    /// SelectionArea has an I-beam waiting there.
    bool handOver(WidgetTester tester, String label) {
      final regions = tester.widgetList<MouseRegion>(
        find.ancestor(of: find.text(label), matching: find.byType(MouseRegion)),
      );

      return regions.isNotEmpty && regions.first.cursor == SystemMouseCursors.click;
    }

    testWidgets('the cursor turns into a hand over a line that goes somewhere', (tester) async {
      // The hand is the whole signal: no underline, so the wording never
      // moves under the pointer.
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Our Privacy Note', 'url': 'https://example.com/privacy'},
          ],
        }),
      );

      expect(handOver(tester, 'Our Privacy Note'), isTrue);
    });

    testWidgets('and the words themselves ask for it, so the selection layer cannot take it back', (tester) async {
      // Found in a browser, not here. The app wraps everything in a
      // SelectionArea so text can be copied, and inside one a Text wraps
      // *itself* in a MouseRegion asking for the I-beam - deeper than the
      // one around the line, so it won and the hand never appeared. The
      // test tree does not reproduce that, so this pins the thing that
      // fixes it: the cursor the words themselves ask for.
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Our Privacy Note', 'url': 'https://example.com/privacy'},
          ],
        }),
      );

      final style = tester
          .widgetList<DefaultSelectionStyle>(
            find.ancestor(of: find.text('Our Privacy Note'), matching: find.byType(DefaultSelectionStyle)),
          )
          .first;

      expect(style.mouseCursor, SystemMouseCursors.click);
    });

    testWidgets('and stays an arrow over one that does not', (tester) async {
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Open Roles'},
          ],
        }),
      );

      expect(handOver(tester, 'Open Roles'), isFalse);
    });

    testWidgets('a line with an address behaves like a link', (tester) async {
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Our Privacy Note', 'url': 'https://example.com/privacy'},
          ],
        }),
      );

      expect(find.text('Our Privacy Note'), findsOneWidget);
      expect(find.ancestor(of: find.text('Our Privacy Note'), matching: find.byType(GestureDetector)), findsOneWidget);
    });

    testWidgets('a line pointing at a page of this app goes there', (tester) async {
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Sign in', 'url': '/login'},
          ],
        }),
      );

      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('an address this page will not follow is not a link at all', (tester) async {
      // Nothing can store one, so this is the second gate rather than the
      // only one - but a page on the open web should not be one bug away
      // from following an address nobody checked.
      await openFooter(
        tester,
        const MarketingContent({}, {
          'footer.productLinks': [
            {'label': 'Open Roles', 'url': 'javascript:alert(1)'},
          ],
        }),
      );

      expect(find.ancestor(of: find.text('Open Roles'), matching: find.byType(GestureDetector)), findsNothing);
    });
  });

  testWidgets('every line of the three columns is a link with no server at all', (tester) async {
    // The page drawing its own copy: before anybody edits it, and
    // whenever the API is down.
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    for (final key in ['footer.productLinks', 'footer.companyLinks', 'footer.resourceLinks']) {
      for (final link in marketingListDefaults[key]!) {
        final label = find.text(link['label']!);

        expect(label, findsOneWidget, reason: link['label']);
        expect(
          find.ancestor(of: label, matching: find.byType(GestureDetector)),
          findsOneWidget,
          reason: '${link['label']} is plain text, not a link',
        );
      }
    }
  });

  testWidgets('the one shipped line pointing at a page of this app works without a server', (tester) async {
    // No document at all - the page drawing its own copy, which is the
    // state it is in before anybody edits it and whenever the API is down.
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Web Dashboard'));
    await tester.tap(find.text('Web Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Login Screen'), findsOneWidget);
  });

  group('the newsletter box', () {
    Future<void> openFooter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester) async {
      final arrow = find.byIcon(Icons.arrow_forward);

      await tester.ensureVisible(arrow);
      await tester.tap(arrow);
      await tester.pumpAndSettle();
    }

    testWidgets('an empty box is asked for an address rather than ignored', (tester) async {
      // It used to do nothing at all, which reads as a broken page.
      await openFooter(tester);

      await send(tester);

      expect(find.text('Enter your email address.'), findsOneWidget);
    });

    testWidgets('something that is not an address is said to be', (tester) async {
      await openFooter(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Enter your email'), 'hello');
      await send(tester);

      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('an address is thanked and the box emptied', (tester) async {
      await openFooter(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Enter your email'), 'head@abbeyroad.test');
      await send(tester);

      expect(find.text("You're on the list"), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget); // the hint is back
    });

    testWidgets('typing again clears the complaint', (tester) async {
      await openFooter(tester);
      await send(tester);

      expect(find.text('Enter your email address.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Enter your email'), 'h');
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address.'), findsNothing);
    });
  });
}
