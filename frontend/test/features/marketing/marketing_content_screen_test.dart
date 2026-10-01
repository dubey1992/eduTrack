import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/marketing/data/marketing_defaults.dart';
import 'package:edutrack_app/features/marketing/data/marketing_draft_repository.dart';
import 'package:edutrack_app/features/marketing/presentation/marketing_content_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_marketing_draft_repository.dart';

Widget wrap(FakeMarketingDraftRepository fake) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [marketingDraftRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: MarketingContentScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder box(String label) => find.widgetWithText(TextFormField, label);

Future<void> type(WidgetTester tester, String label, String text) async {
  await tester.enterText(box(label), text);
  await tester.pump();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The Super Admin's homepage editor (docs/marketing-content.md, slice 2).
///
/// The rule running through all of it: saving is not publishing. Everything
/// typed here stays off the public page until somebody presses Publish and
/// confirms it.
void main() {
  group('loading the editor', () {
    testWidgets('shows a spinner while the draft loads', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository()..getGate = Completer<void>();

      await tester.pumpWidget(wrap(fake));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      fake.getGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a failed load offers a retry rather than a blank screen', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(failGetWith: Failure.unknown('Server unreachable'));

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Server unreachable'), findsOneWidget);

      fake.failGetWith = null;
      await tapButton(tester, 'Retry');

      expect(box('Headline'), findsOneWidget);
    });

    testWidgets('it draws a box for every field the server declares', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();

      expect(box('Headline'), findsOneWidget);
      expect(box('Opening paragraph'), findsOneWidget);
      expect(box('Button'), findsOneWidget);
    });

    testWidgets('it groups the boxes under the sections of the page', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();

      expect(find.text('The opening'), findsOneWidget);
      expect(find.text('The invitation'), findsOneWidget);
      expect(find.text('The headline and the first paragraph anybody reads.'), findsOneWidget);
    });

    testWidgets('a box left alone shows the words that ship, so it is never a mystery', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Leave empty to use: ${marketingDefaults['cta.button']}'), findsOneWidget);
    });

    testWidgets('it opens with whatever was being worked on', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'Half a thought'});

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Half a thought'), findsOneWidget);
    });
  });

  group('whether the page is up to date', () {
    testWidgets('it says when a draft is waiting to be published', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(
        draft: {'hero.headline': 'New'},
        published: {'hero.headline': 'Live'},
        publishedAt: DateTime(2026, 9, 30, 14, 5),
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Draft not published'), findsOneWidget);
      expect(find.text('Visitors are still reading the published words. Publish when you are ready.'), findsOneWidget);
    });

    testWidgets('it says so when the page already matches', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(
        draft: {'hero.headline': 'Live'},
        published: {'hero.headline': 'Live'},
        publishedAt: DateTime(2026, 9, 30, 14, 5),
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('The homepage matches this draft'), findsOneWidget);
    });

    testWidgets('a page nobody has published says so rather than showing a blank date', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Never published.'), findsOneWidget);
      expect(find.text('The homepage shows the words the app ships with.'), findsOneWidget);
    });

    testWidgets('the publish date is in the format the rest of the app uses', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(publishedAt: DateTime(2026, 9, 30, 14, 5));

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.textContaining('09/30/2026'), findsOneWidget);
    });
  });

  group('saving a draft', () {
    testWidgets('it sends what was typed', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Run Your School Smarter');
      await tapButton(tester, 'Save Draft');

      expect(fake.lastSave!['hero.headline'], 'Run Your School Smarter');
    });

    testWidgets('an empty box is left out, so the page falls back to what it ships with', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'Was changed'});

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', '');
      await tapButton(tester, 'Save Draft');

      expect(fake.lastSave, isNot(contains('hero.headline')));
    });

    testWidgets('it says the save landed, and that the page has not changed yet', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'New words');
      await tapButton(tester, 'Save Draft');

      expect(find.text('Draft saved. The homepage still shows the published words.'), findsOneWidget);
    });

    testWidgets('a second tap while saving does not send it twice', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository()..saveGate = Completer<void>();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Once');

      await tester.ensureVisible(find.text('Save Draft'));
      await tester.tap(find.text('Save Draft'));
      await tester.pump();
      await tester.tap(find.text('Save Draft'), warnIfMissed: false);
      await tester.pump();

      expect(fake.saveCalls, 1);

      fake.saveGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a refused save says why, and leaves the typing on screen', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(
        failSaveWith: const Failure(
          code: 'VALIDATION_ERROR',
          message: 'Please correct the highlighted fields.',
          details: {
            'errors': {
              'document': ['Headline must be 90 characters or fewer - it is 120.'],
            },
          },
        ),
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Something long');
      await tapButton(tester, 'Save Draft');

      expect(find.text('Please correct the highlighted fields.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Something long'), findsOneWidget);
    });

    testWidgets("the server's complaint is shown on the box it is about", (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(
        failSaveWith: const Failure(
          code: 'VALIDATION_ERROR',
          message: 'Please correct the highlighted fields.',
          details: {
            'errors': {
              'document': ['Button must be 32 characters or fewer - it is 40.'],
            },
          },
        ),
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Button', 'A very long call to action indeed, truly');
      await tapButton(tester, 'Save Draft');

      final field = tester.widget<TextField>(find.descendant(of: box('Button'), matching: find.byType(TextField)));
      expect(field.decoration!.errorText, 'Button must be 32 characters or fewer - it is 40.');
    });
  });

  group('what the form refuses before asking the server', () {
    testWidgets('a headline longer than its slot is caught here', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'x' * 91);
      await tapButton(tester, 'Save Draft');

      expect(find.text('Headline must be 90 characters or fewer - it is 91.'), findsOneWidget);
      expect(fake.saveCalls, 0, reason: 'nothing should have been sent');
    });

    testWidgets('a headline exactly as long as its slot is fine', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'x' * 90);
      await tapButton(tester, 'Save Draft');

      expect(fake.saveCalls, 1);
    });

    testWidgets('a paragraph may run on to its own larger limit', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Opening paragraph', 'x' * 250);
      await tapButton(tester, 'Save Draft');

      expect(fake.saveCalls, 1);
    });
  });

  group('previewing', () {
    testWidgets('it shows the homepage with the words in the boxes', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Run Your School Smarter');
      await tapButton(tester, 'Preview');

      expect(find.text('Run Your School Smarter'), findsWidgets);
    });

    testWidgets('it previews what is typed, without saving it first', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Not saved yet');
      await tapButton(tester, 'Preview');

      expect(fake.saveCalls, 0);
      expect(find.text('Not saved yet'), findsWidgets);
    });

    testWidgets('it says plainly that this is not the live page', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Preview');

      expect(find.text('Preview - these words are not published yet.'), findsOneWidget);
    });

    testWidgets('closing it comes back to the editor with the typing intact', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Still here');
      await tapButton(tester, 'Preview');

      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Still here'), findsOneWidget);
    });
  });

  group('publishing', () {
    Future<void> openPublishDialog(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Publish'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Publish'));
      await tester.pumpAndSettle();
    }

    Future<void> publish(WidgetTester tester, {bool confirm = true}) async {
      await openPublishDialog(tester);
      // The dialog's buttons, not the screen's - "Publish" names both.
      await tester.tap(find.widgetWithText(confirm ? FilledButton : TextButton, confirm ? 'Publish' : 'Cancel'));
      await tester.pumpAndSettle();
    }

    testWidgets('it asks before putting the words in front of the world', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository(draft: {'hero.headline': 'New'})));
      await tester.pumpAndSettle();
      await openPublishDialog(tester);

      expect(find.text('Publish the homepage?'), findsOneWidget);
      expect(find.text('Everyone visiting the site will see these words straight away.'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('changing your mind publishes nothing', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'New'});

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await publish(tester, confirm: false);

      expect(fake.publishCalls, 0);
    });

    testWidgets('confirming publishes, and says so', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'New'});

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await publish(tester);

      expect(fake.publishCalls, 1);
      expect(find.text('Published. Visitors see the new words now.'), findsOneWidget);
    });

    testWidgets('afterwards the screen stops saying a draft is waiting', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'New'});

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      expect(find.text('Draft not published'), findsOneWidget);
      expect(find.text('Nothing here is live yet. Publish when you are ready.'), findsOneWidget);

      await publish(tester);

      expect(find.text('The homepage matches this draft'), findsOneWidget);
      expect(find.text('Everything here is what visitors see.'), findsOneWidget);
    });

    testWidgets('a failed publish says so and leaves the draft alone', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(
        draft: {'hero.headline': 'New'},
        failPublishWith: Failure.unknown('Could not reach the server.'),
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await publish(tester);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Draft not published'), findsOneWidget);
    });

    testWidgets('publishing saves the boxes first, so what is on screen is what goes live', (tester) async {
      // Pressing Publish with unsaved typing on screen means "put this on
      // the homepage". Publishing the last saved draft instead would be
      // technically defensible and completely baffling.
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'Saved a while ago'});

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'Typed just now');
      await publish(tester);

      expect(fake.published, {'hero.headline': 'Typed just now'});
    });

    testWidgets('a box the form refuses stops the publish before it is asked about', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'x' * 91);
      await openPublishDialog(tester);

      expect(find.text('Publish the homepage?'), findsNothing);
      expect(fake.publishCalls, 0);
    });
  });

  group('the repeating lists', () {
    testWidgets('a list opens on the one the page ships with', (tester) async {
      // There is no placeholder to show a shipped list in, so the editor
      // starts from it rather than from an empty form.
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();

      expect(find.text('The figures under the hero'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Schools (Target)'), findsOneWidget);
    });

    testWidgets('a saved list opens on what was saved', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository()
        ..draftLists = {
          'hero.stats': [
            {'value': '12', 'label': 'Schools signed up'},
          ],
        };

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Schools signed up'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Schools (Target)'), findsNothing);
    });

    testWidgets('the lists go to the server beside the words', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await type(tester, 'Headline', 'New words');
      await tapButton(tester, 'Save Draft');

      expect(fake.lastSave!['hero.headline'], 'New words');
      expect(fake.lastSave!['hero.stats'], marketingListDefaults['hero.stats']);
    });

    testWidgets('an item edited in the list is what gets sent', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '500+'), '12');
      await tester.pump();
      await tapButton(tester, 'Save Draft');

      expect((fake.lastSave!['hero.stats']! as List).first, {
        'source': 'typed',
        'value': '12',
        'label': 'Schools (Target)',
      });
    });

    testWidgets('a blank box in an item stops the save before it is sent', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository();

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '500+'), '');
      await tester.pump();
      await tapButton(tester, 'Save Draft');

      expect(fake.saveCalls, 0);
      expect(find.text('Every Figure needs a figure.'), findsOneWidget);
    });

    testWidgets('previewing shows the page with the edited list', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeMarketingDraftRepository()));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Schools (Target)'), 'Schools signed up');
      await tester.pump();
      await tapButton(tester, 'Preview');

      expect(find.text('Schools signed up'), findsWidgets);
    });
  });

  group('figures that count something real', () {
    testWidgets('the preview draws the count, not the typed fallback', (tester) async {
      // The page is only ever handed numbers somebody else resolved, so
      // the preview has to resolve them before handing them over.
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(figures: {'schools': 1248})
        ..draftLists = {
          'hero.stats': [
            {'source': 'schools', 'value': '500+', 'label': 'Schools'},
          ],
        };

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Preview');

      // Scoped to the preview: the editor's own boxes are still behind it,
      // and one of them holds the typed fallback.
      Finder inPreview(String text) => find.descendant(of: find.byType(Dialog), matching: find.text(text));

      expect(inPreview('1,248'), findsWidgets);
      expect(inPreview('500+'), findsNothing);
    });

    testWidgets('a platform with nothing to count previews the typed figure', (tester) async {
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(figures: {'schools': 0})
        ..draftLists = {
          'hero.stats': [
            {'source': 'schools', 'value': '500+', 'label': 'Schools'},
          ],
        };

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Preview');

      expect(find.descendant(of: find.byType(Dialog), matching: find.text('500+')), findsWidgets);
    });

    testWidgets('what gets saved is the choice, not the number', (tester) async {
      // Otherwise publishing would freeze the count into the document and
      // the figure would stop being live.
      useDesktop(tester);
      final fake = FakeMarketingDraftRepository(figures: {'schools': 1248})
        ..draftLists = {
          'hero.stats': [
            {'source': 'schools', 'value': '500+', 'label': 'Schools'},
          ],
        };

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save Draft');

      expect((fake.lastSave!['hero.stats']! as List).single, {
        'source': 'schools',
        'value': '500+',
        'label': 'Schools',
      });
    });
  });
}
