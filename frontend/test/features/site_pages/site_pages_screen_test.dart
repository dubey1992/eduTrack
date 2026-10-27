import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/site_pages/data/site_page_repository.dart';
import 'package:edutrack_app/features/site_pages/presentation/site_page_editor.dart';
import 'package:edutrack_app/features/site_pages/presentation/site_page_screen.dart';
import 'package:edutrack_app/features/site_pages/presentation/site_pages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_site_page_repository.dart';

/// Website Pages (docs/site-pages.md): the Super Admin's list and editor,
/// and the public page a visitor reads.
///
/// The rule running through the editor is the homepage's: saving is not
/// publishing. Nothing typed reaches the public page until Publish is
/// pressed and confirmed.

late GoRouter _router;

Widget wrap(FakeSitePageRepository fake, {String at = '/site-pages'}) {
  _router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('Homepage')),
      ),
      GoRoute(
        path: '/site-pages',
        builder: (context, state) => Scaffold(
          body: SitePagesScreen(
            editing: state.uri.queryParameters['page'],
            creating: state.uri.queryParameters['new'] != null,
          ),
        ),
      ),
      GoRoute(
        path: '/pages/:slug',
        builder: (context, state) => SitePageScreen(slug: state.pathParameters['slug']!),
      ),
    ],
  );

  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [sitePageRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: _router),
  );
}

String get location => _router.routerDelegate.currentConfiguration.uri.toString();

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder box(String label) => find.widgetWithText(TextFormField, label);

Finder get bodyBox => find.byWidgetPredicate((w) => w is TextField && w.keyboardType == TextInputType.multiline);

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('the list', () {
    testWidgets('shows every page with its status, and only added pages can be deleted', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository(
        pages: [
          ...FakeSitePageRepository.builtIns(),
          FakePage(slug: 'careers', title: 'Careers', body: 'Join us'),
        ],
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      for (final title in ['About Us', 'Privacy Policy', 'Terms of Use', 'Careers']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Live'), findsNWidgets(2));
      expect(find.text('Not published'), findsNWidgets(2));
      expect(find.text('Built-in'), findsNWidgets(3));
      expect(find.byTooltip('Delete page'), findsOneWidget);
    });

    testWidgets('a list that cannot be loaded says so and can be retried', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository()..failListWith = Failure.network();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);

      fake.failListWith = null;
      await tapText(tester, 'Retry');

      expect(find.text('About Us'), findsOneWidget);
    });

    testWidgets('deleting asks first, in the app, and takes the page off the list', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository(
        pages: [
          ...FakeSitePageRepository.builtIns(),
          FakePage(slug: 'careers', title: 'Careers', body: 'Join us'),
        ],
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete page'));
      await tester.pumpAndSettle();

      expect(find.text('Delete "Careers"?'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(fake.deleted, isEmpty);

      await tester.tap(find.byTooltip('Delete page'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');

      expect(fake.deleted, ['careers']);
      expect(find.text('Careers'), findsNothing);
      expect(find.text('"Careers" deleted.'), findsOneWidget);
    });

    testWidgets('a refused delete says why and keeps the page', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository(
        pages: [
          ...FakeSitePageRepository.builtIns(),
          FakePage(slug: 'careers', title: 'Careers', body: 'Join us'),
        ],
      )..failDeleteWith = const Failure(code: 'SERVER_ERROR', message: 'Something went wrong on our side.');

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete page'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');

      expect(find.text('Something went wrong on our side.'), findsOneWidget);
      expect(find.text('Careers'), findsOneWidget);
    });

    testWidgets('Edit opens the editor for that page', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').at(2));
      await tester.pumpAndSettle();

      expect(location, '/site-pages?page=terms');
      expect(find.byType(SitePageEditor), findsOneWidget);
    });
  });

  group('editing a built-in page', () {
    testWidgets('its address cannot be changed', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.descendant(of: box('Address'), matching: find.byType(TextField))).enabled,
        isFalse,
      );
      expect(find.text('Built-in pages keep their address.'), findsOneWidget);
    });

    testWidgets('saving is not publishing', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository();

      await tester.pumpWidget(wrap(fake, at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();

      await tester.enterText(bodyBox, '## Your account\n\nAcme Ltd');
      await tester.pump();
      expect(find.text('You have unsaved changes.'), findsOneWidget);

      await tapText(tester, 'Save Draft');

      expect(fake.saves.single.body, '## Your account\n\nAcme Ltd');
      expect(fake.published, isEmpty);
      expect(find.text('Draft saved.'), findsOneWidget);
      expect(find.text('You have unsaved changes.'), findsNothing);
      expect(find.text('Not published'), findsOneWidget);
    });

    testWidgets('Publish asks first, then saves what is on screen and publishes it', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository();

      await tester.pumpWidget(wrap(fake, at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();
      await tester.enterText(bodyBox, 'Final words');
      await tester.pump();

      await tapText(tester, 'Publish');
      expect(find.text('Publish "Terms of Use"?'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(fake.published, isEmpty);

      await tapText(tester, 'Publish');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(fake.saves.single.body, 'Final words');
      expect(fake.published, ['terms']);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('View live page'), findsOneWidget);
    });

    testWidgets('what the server refuses is shown against the box it names', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository()
        ..failSaveWith = const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'body': ['The link "Click" can\'t be used: an address has to start with https://.'],
            },
          },
        );

      await tester.pumpWidget(wrap(fake, at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Save Draft');

      expect(find.text('The given data was invalid.'), findsOneWidget);
      expect(find.textContaining('The link "Click" can\'t be used'), findsOneWidget);
    });

    testWidgets('a title is required', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository();

      await tester.pumpWidget(wrap(fake, at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();
      await tester.enterText(box('Page title'), '  ');
      await tapText(tester, 'Save Draft');

      expect(find.text('Give the page a title.'), findsOneWidget);
      expect(fake.saves, isEmpty);
    });

    testWidgets('the preview follows the box as it is typed into', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();

      await tester.enterText(bodyBox, '## A brand new heading');
      await tester.pump();

      // Once in the box, once drawn in the preview.
      expect(find.text('A brand new heading', findRichText: true), findsOneWidget);
    });

    testWidgets('the Bold button wraps what is selected', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();

      await tester.enterText(bodyBox, 'make this bold');
      final field = tester.widget<TextField>(bodyBox);
      field.controller!.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();

      expect(field.controller!.text, 'make **this** bold');
    });

    testWidgets('the Link button refuses an address the page would not follow', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();

      await tester.enterText(bodyBox, '');
      await tester.tap(find.byTooltip('Link'));
      await tester.pumpAndSettle();

      await tester.enterText(box('Words to show'), 'Click');
      // The editor has an Address box too; the dialog's is the last one.
      await tester.enterText(box('Address').last, 'javascript:alert(1)');
      await tapText(tester, 'Add link');

      expect(find.textContaining('Start with https://'), findsOneWidget);

      await tester.enterText(box('Address').last, '/privacy');
      await tapText(tester, 'Add link');

      expect(tester.widget<TextField>(bodyBox).controller!.text, '[Click](/privacy)');
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();
      await tester.enterText(bodyBox, 'Half written');
      await tester.pump();

      await tapText(tester, 'All pages');
      expect(find.text('Leave without saving?'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(location, '/site-pages?page=terms');

      await tapText(tester, 'All pages');
      await tapText(tester, 'Leave');
      expect(location, '/site-pages');
    });

    testWidgets('on a phone the box and the preview take turns', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?page=terms'));
      await tester.pumpAndSettle();

      expect(find.text('PREVIEW'), findsNothing);

      await tapText(tester, 'Preview');

      expect(find.text('PREVIEW'), findsOneWidget);
    });
  });

  group('adding a page', () {
    testWidgets('the address follows the title until somebody types one', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/site-pages?new=1'));
      await tester.pumpAndSettle();

      await tester.enterText(box('Page title'), 'Help & Support');
      await tester.pump();
      expect(find.text('help-and-support'), findsOneWidget);

      await tester.enterText(box('Address'), 'help');
      await tester.enterText(box('Page title'), 'Help Centre');
      await tester.pump();
      expect(find.text('help'), findsOneWidget);
    });

    testWidgets('an address that cannot be one is refused before the server is asked', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository();

      await tester.pumpWidget(wrap(fake, at: '/site-pages?new=1'));
      await tester.pumpAndSettle();
      await tester.enterText(box('Page title'), 'Careers');
      await tester.enterText(box('Address'), 'Careers Page');
      await tapText(tester, 'Save Draft');

      expect(find.textContaining('Use lowercase letters, numbers and single hyphens'), findsOneWidget);
      expect(fake.creates, isEmpty);
    });

    testWidgets('saving creates it as a draft and opens it at its address', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository();

      await tester.pumpWidget(wrap(fake, at: '/site-pages?new=1'));
      await tester.pumpAndSettle();
      await tester.enterText(box('Page title'), 'Careers');
      await tester.enterText(bodyBox, 'We are hiring.');
      await tapText(tester, 'Save Draft');

      expect(fake.creates.single, (slug: 'careers', title: 'Careers', body: 'We are hiring.'));
      expect(fake.published, isEmpty);
      expect(location, '/site-pages?page=careers');
      expect(find.text('Not published'), findsOneWidget);
    });

    testWidgets('a taken address is reported against the address box', (tester) async {
      useDesktop(tester);
      final fake = FakeSitePageRepository()
        ..failSaveWith = const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'slug': ['That address is already used by another page.'],
            },
          },
        );

      await tester.pumpWidget(wrap(fake, at: '/site-pages?new=1'));
      await tester.pumpAndSettle();
      await tester.enterText(box('Page title'), 'About');
      await tapText(tester, 'Save Draft');

      expect(find.text('That address is already used by another page.'), findsOneWidget);
      expect(location, '/site-pages?new=1');
    });
  });

  group('the public page', () {
    testWidgets('shows the published title, date and text - never the draft', (tester) async {
      final fake = FakeSitePageRepository();
      fake.pages[1].body = 'An unpublished draft';

      await tester.pumpWidget(wrap(fake, at: '/pages/privacy'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Last updated 10/26/2026'), findsOneWidget);
      expect(find.text('Who can see it'), findsOneWidget);
      expect(find.textContaining('An unpublished draft'), findsNothing);
    });

    testWidgets('waits with a spinner rather than an empty page', (tester) async {
      final fake = FakeSitePageRepository()..publishedGate = Completer<void>();

      await tester.pumpWidget(wrap(fake, at: '/pages/about'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      fake.publishedGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('About Us'), findsOneWidget);
    });

    testWidgets('a page that is not published is "not available", with a way home', (tester) async {
      await tester.pumpWidget(wrap(FakeSitePageRepository(), at: '/pages/terms'));
      await tester.pumpAndSettle();

      expect(find.text('This page is not available'), findsOneWidget);

      await tapText(tester, 'Go to the homepage');
      expect(location, '/');
    });

    testWidgets('a page that could not be loaded can be tried again', (tester) async {
      final fake = FakeSitePageRepository()..failPublishedWith = Failure.network();

      await tester.pumpWidget(wrap(fake, at: '/pages/about'));
      await tester.pumpAndSettle();

      expect(find.text('This page could not be loaded'), findsOneWidget);

      fake.failPublishedWith = null;
      await tapText(tester, 'Try again');

      expect(find.text('About Us'), findsOneWidget);
    });

    testWidgets('a link with an address the page will not follow is plain words', (tester) async {
      final fake = FakeSitePageRepository(
        pages: [
          FakePage(
            slug: 'help',
            title: 'Help',
            publishedTitle: 'Help',
            publishedBody: 'Read [the policy](/privacy) or [this](javascript:alert(1)).',
          ),
        ],
      );

      await tester.pumpWidget(wrap(fake, at: '/pages/help'));
      await tester.pumpAndSettle();

      final paragraph = tester.widget<RichText>(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('Read ')),
      );
      final spans = <TextSpan>[];
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });

      expect(spans.firstWhere((s) => s.text == 'the policy').recognizer, isNotNull);
      expect(spans.where((s) => s.text == 'this').every((s) => s.recognizer == null), isTrue);
    });
  });
}
