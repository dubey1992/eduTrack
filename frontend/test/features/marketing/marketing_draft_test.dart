import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/marketing/application/marketing_draft_notifier.dart';
import 'package:edutrack_app/features/marketing/data/marketing_content.dart';
import 'package:edutrack_app/features/marketing/data/marketing_content_repository.dart';
import 'package:edutrack_app/features/marketing/data/marketing_defaults.dart';
import 'package:edutrack_app/features/marketing/data/marketing_draft_repository.dart';
import 'package:edutrack_app/features/marketing/data/models/marketing_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_marketing_draft_repository.dart';

/// The editor's data layer (docs/marketing-content.md, slice 2).
void main() {
  group('reading what the server sent', () {
    test('it takes the form, the draft and the published page out of it', () {
      final draft = MarketingDraft.fromJson({
        'sections': [
          {
            'key': 'hero',
            'label': 'The opening',
            'description': 'The first thing anybody reads.',
            'fields': [
              {'key': 'hero.headline', 'label': 'Headline', 'multiline': false, 'max_length': 90, 'help': 'Set large.'},
            ],
          },
        ],
        'draft': {'hero.headline': 'Being written'},
        'published': {'hero.headline': 'Live'},
        'published_at': '2026-09-30T14:05:00Z',
        'has_unpublished_changes': true,
      });

      expect(draft.sections.single.label, 'The opening');
      expect(draft.fields.single.maxLength, 90);
      expect(draft.fields.single.multiline, isFalse);
      expect(draft.draft, {'hero.headline': 'Being written'});
      expect(draft.published, {'hero.headline': 'Live'});
      expect(draft.hasUnpublishedChanges, isTrue);
      expect(draft.publishedAt, isNotNull);
    });

    test('a page nobody has published reads back as never published', () {
      final draft = MarketingDraft.fromJson({
        'sections': <dynamic>[],
        'draft': <String, dynamic>{},
        'published': <String, dynamic>{},
        'published_at': null,
        'has_unpublished_changes': false,
      });

      expect(draft.publishedAt, isNull);
      expect(draft.hasUnpublishedChanges, isFalse);
    });

    test('a shape nobody expected is an empty form, not a crash', () {
      for (final body in <Map<String, dynamic>>[
        {},
        {'sections': null, 'draft': 'nonsense', 'published': 42},
        {'sections': 'nonsense', 'published_at': 'not a date'},
      ]) {
        final draft = MarketingDraft.fromJson(body);

        expect(draft.sections, isEmpty, reason: '$body');
        expect(draft.draft, isEmpty, reason: '$body');
        expect(draft.publishedAt, isNull, reason: '$body');
      }
    });

    test('a field with no length declared still gets a usable one', () {
      // Better a sensible cap than a box that silently accepts anything
      // and is refused by the server on save.
      final field = MarketingField.fromJson({'key': 'hero.headline', 'label': 'Headline'});

      expect(field.maxLength, greaterThan(0));
    });

    test('a field knows the words the page shows when it is left alone', () {
      final field = MarketingField.fromJson({'key': 'cta.button', 'label': 'Button'});

      expect(field.shipped, marketingDefaults['cta.button']);
    });
  });

  group('the notifier', () {
    ProviderContainer containerFor(FakeMarketingDraftRepository fake) {
      final container = ProviderContainer(overrides: [marketingDraftRepositoryProvider.overrideWithValue(fake)]);
      addTearDown(container.dispose);

      return container;
    }

    test('it loads the draft', () async {
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'Being written'});
      final container = containerFor(fake);

      final draft = await container.read(marketingDraftNotifierProvider.future);

      expect(draft.draft, {'hero.headline': 'Being written'});
    });

    test('a save replaces what is on screen with what the server kept', () async {
      final fake = FakeMarketingDraftRepository();
      final container = containerFor(fake);
      await container.read(marketingDraftNotifierProvider.future);

      await container.read(marketingDraftNotifierProvider.notifier).save({'hero.headline': 'Saved'});

      expect(container.read(marketingDraftNotifierProvider).value!.draft, {'hero.headline': 'Saved'});
    });

    test('a failed save throws rather than blanking the screen', () async {
      final fake = FakeMarketingDraftRepository(
        draft: {'hero.headline': 'Still here'},
        failSaveWith: const Failure(code: 'VALIDATION_ERROR', message: 'No.'),
      );
      final container = containerFor(fake);
      await container.read(marketingDraftNotifierProvider.future);

      await expectLater(
        container.read(marketingDraftNotifierProvider.notifier).save({'hero.headline': 'x'}),
        throwsA(isA<Failure>()),
      );
      expect(container.read(marketingDraftNotifierProvider).value!.draft, {'hero.headline': 'Still here'});
    });

    test('publishing reads the row back, so the screen stops offering to publish', () async {
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'New'});
      final container = containerFor(fake);
      await container.read(marketingDraftNotifierProvider.future);

      await container.read(marketingDraftNotifierProvider.notifier).publish();

      final draft = container.read(marketingDraftNotifierProvider).value!;
      expect(draft.hasUnpublishedChanges, isFalse);
      expect(draft.publishedAt, isNotNull);
    });

    test('publishing forgets the homepage words this app was holding', () async {
      // The Super Admin is about to look at the homepage to check their
      // work, and this app may still be showing the old wording.
      final fake = FakeMarketingDraftRepository(draft: {'hero.headline': 'New'});
      final container = ProviderContainer(
        overrides: [
          marketingDraftRepositoryProvider.overrideWithValue(fake),
          marketingContentRepositoryProvider.overrideWithValue(_StaleContent()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(marketingDraftNotifierProvider.future);
      container.read(marketingContentProvider);
      final before = _StaleContent.fetches;

      await container.read(marketingDraftNotifierProvider.notifier).publish();
      container.read(marketingContentProvider);

      expect(_StaleContent.fetches, greaterThan(before));
    });
  });
}

class _StaleContent implements MarketingContentRepository {
  static int fetches = 0;

  @override
  Future<MarketingContent> fetch() async {
    fetches++;
    return const MarketingContent.asItShips();
  }
}
