import 'dart:typed_data';

import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/site_pages/data/models/site_page.dart';
import 'package:edutrack_app/features/site_pages/data/site_page_repository.dart';
import 'package:edutrack_app/features/site_pages/presentation/site_pages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_site_page_repository.dart';

/// The blog and the help centre in the Website Pages editor (docs/seo.md,
/// S5): a post has a summary, an author and a cover image; a help article a
/// summary and a topic; a plain page neither.

late GoRouter _router;

Widget _wrap(FakeSitePageRepository fake, {String at = '/site-pages'}) {
  _router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: '/site-pages',
        builder: (context, state) => Scaffold(
          body: SitePagesScreen(
            editing: state.uri.queryParameters['page'],
            creating: state.uri.queryParameters['new'] != null,
            newKind: SitePageKind.fromApiValue(state.uri.queryParameters['new']),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [sitePageRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: _router),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _box(String label) => find.widgetWithText(TextFormField, label);

/// The page text box: the multi-line box with no line limit (the summary
/// is multi-line too, but capped at three).
Finder get _body =>
    find.byWidgetPredicate((w) => w is TextField && w.keyboardType == TextInputType.multiline && w.maxLines == null);

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

FakePage _post({bool hasCover = false}) => FakePage(
  slug: 'first-post',
  title: 'First post',
  body: 'Hello.',
  kind: SitePageKind.post,
  summary: 'A first post.',
  author: 'School365ai Team',
  hasCover: hasCover,
);

void main() {
  group('writing a new one', () {
    testWidgets('a page asks for none of the extras', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(FakeSitePageRepository(), at: '/site-pages?new=1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('page-kind')), findsOneWidget);
      expect(find.byKey(const Key('page-summary')), findsNothing);
      expect(find.byKey(const Key('page-topic')), findsNothing);
      expect(find.text('Cover image'), findsNothing);
    });

    testWidgets('choosing Blog post asks for a summary, an author and a cover, at /blog/', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(FakeSitePageRepository(), at: '/site-pages?new=1'));
      await tester.pumpAndSettle();

      await _tap(tester, 'Blog post');

      expect(_box('Post title'), findsOneWidget);
      expect(find.byKey(const Key('page-summary')), findsOneWidget);
      expect(tester.widget<TextFormField>(_box('Author')).controller!.text, 'School365ai Team');
      expect(find.text('Save the post first, then add a cover image.'), findsOneWidget);
      expect(find.textContaining('/blog/'), findsWidgets);
    });

    testWidgets('a post is saved as a post, with its summary and author', (tester) async {
      _desktop(tester);
      final fake = FakeSitePageRepository();
      await tester.pumpWidget(_wrap(fake, at: '/site-pages?new=post'));
      await tester.pumpAndSettle();

      await tester.enterText(_box('Post title'), 'Why alerts matter');
      await tester.enterText(find.byKey(const Key('page-summary')), 'Same-morning alerts, and why.');
      await tester.enterText(_box('Author'), 'Priya Nair');
      await tester.enterText(_body, 'Hello.');
      await _tap(tester, 'Save Draft');

      final created = fake.creates.single;
      expect((created.kind, created.slug), (SitePageKind.post, 'why-alerts-matter'));
      expect(created.details.toJson(), {'summary': 'Same-morning alerts, and why.', 'author': 'Priya Nair'});
    });

    testWidgets('a post needs a summary', (tester) async {
      _desktop(tester);
      final fake = FakeSitePageRepository();
      await tester.pumpWidget(_wrap(fake, at: '/site-pages?new=post'));
      await tester.pumpAndSettle();

      await tester.enterText(_box('Post title'), 'No summary');
      await _tap(tester, 'Save Draft');

      expect(find.text('Write a summary - it is shown under the title in the list.'), findsOneWidget);
      expect(fake.creates, isEmpty);
    });

    testWidgets('a help article needs a topic, and sends it', (tester) async {
      _desktop(tester);
      final fake = FakeSitePageRepository();
      await tester.pumpWidget(_wrap(fake, at: '/site-pages?new=help'));
      await tester.pumpAndSettle();

      await tester.enterText(_box('Article title'), 'Take the register');
      await tester.enterText(find.byKey(const Key('page-summary')), 'How to take it.');
      await _tap(tester, 'Save Draft');

      expect(find.text('Choose the topic this article belongs under.'), findsOneWidget);
      expect(fake.creates, isEmpty);

      await tester.tap(find.byKey(const Key('page-topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attendance').last);
      await tester.pumpAndSettle();
      await _tap(tester, 'Save Draft');

      expect(fake.creates.single.kind, SitePageKind.help);
      expect(fake.creates.single.details.toJson(), {'summary': 'How to take it.', 'topic': 'attendance'});
    });
  });

  group('editing one', () {
    testWidgets('its kind is fixed and its details are there to change', (tester) async {
      _desktop(tester);
      final fake = FakeSitePageRepository(pages: [_post()]);
      await tester.pumpWidget(_wrap(fake, at: '/site-pages?page=first-post'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('page-kind')), findsNothing);
      expect(tester.widget<TextFormField>(find.byKey(const Key('page-summary'))).controller!.text, 'A first post.');

      await tester.enterText(find.byKey(const Key('page-summary')), 'A better summary.');
      await _tap(tester, 'Save Draft');

      expect(fake.detailsSaved.single.summary, 'A better summary.');
    });

    testWidgets('a saved post shows its cover, and the cover can be removed', (tester) async {
      _desktop(tester);
      final fake = FakeSitePageRepository(pages: [_post(hasCover: true)])
        ..coverPreview = Uint8List.fromList(_onePixelPng);
      await tester.pumpWidget(_wrap(fake, at: '/site-pages?page=first-post'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cover-preview')), findsOneWidget);
      expect(find.text('Change image'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('cover-remove')));
      await tester.tap(find.byKey(const Key('cover-remove')));
      await tester.pumpAndSettle();
      await _tap(tester, 'Remove');

      expect(fake.coverRemovals, ['first-post']);
      expect(find.text('Choose image'), findsOneWidget);
      expect(find.text('Cover image removed.'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('shows one kind at a time, and its New button makes that kind', (tester) async {
      _desktop(tester);
      final fake = FakeSitePageRepository(pages: [...FakeSitePageRepository.builtIns(), _post()]);
      await tester.pumpWidget(_wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('About Us'), findsOneWidget);
      expect(find.text('First post'), findsOneWidget);

      await _tap(tester, 'Blog posts');

      expect(find.text('About Us'), findsNothing);
      expect(find.text('First post'), findsOneWidget);
      expect(find.textContaining('/blog/first-post'), findsOneWidget);

      await _tap(tester, 'New Blog Post');

      expect(_box('Post title'), findsOneWidget);
    });

    testWidgets('an empty kind says so', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(FakeSitePageRepository()));
      await tester.pumpAndSettle();

      await _tap(tester, 'Help articles');

      expect(find.text('No help articles yet.'), findsOneWidget);
    });
  });
}

/// The smallest valid PNG: one transparent pixel.
const _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
];
