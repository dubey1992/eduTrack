import 'package:edutrack_app/features/marketing/data/marketing_content.dart';
import 'package:edutrack_app/features/marketing/presentation/marketing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/marketing_scope.dart';

Widget wrap({MarketingContent content = const MarketingContent.asItShips()}) {
  return marketingScope(
    content: content,
    MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const MarketingScreen()),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
        ],
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

  testWidgets('tapping Login navigates to the login route', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login Screen'), findsOneWidget);
  });

  testWidgets('tapping Join Early Access opens the signup form, not a JS alert', (tester) async {
    // Tall enough for the form; the dialog scrolls, but the fields have to
    // exist to be found.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Join Early Access').first);
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
}
