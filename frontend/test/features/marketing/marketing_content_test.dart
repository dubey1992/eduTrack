import 'package:edutrack_app/features/marketing/data/marketing_content.dart';
import 'package:edutrack_app/features/marketing/data/marketing_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

/// The homepage's words (docs/marketing-content.md, slice 1).
///
/// The rule the whole slice rests on: the page renders its own copy when
/// the server has nothing to say, has not answered yet, or cannot. A
/// marketing homepage that goes blank because an API call did would be
/// worse than one nobody can edit.
void main() {
  group('what the page says', () {
    test('an unedited page says exactly what it ships with', () {
      const content = MarketingContent.asItShips();

      expect(content.text('hero.headline'), marketingDefaults['hero.headline']);
      expect(content.text('nav.wordmark'), 'School365ai');
    });

    test('a changed word replaces the one that ships', () {
      const content = MarketingContent({'hero.headline': 'Run Your School Better'});

      expect(content.text('hero.headline'), 'Run Your School Better');
    });

    test('a word nobody changed still comes from the defaults', () {
      const content = MarketingContent({'hero.headline': 'Changed'});

      expect(content.text('hero.body'), marketingDefaults['hero.body']);
    });

    test('an emptied field falls back rather than leaving a hole', () {
      // Clearing a box in the editor should not leave the homepage with a
      // blank headline for everybody who visits it.
      const content = MarketingContent({'hero.headline': '', 'hero.body': '   '});

      expect(content.text('hero.headline'), marketingDefaults['hero.headline']);
      expect(content.text('hero.body'), marketingDefaults['hero.body']);
    });
  });

  group('reading what the server sent', () {
    test('it takes the changed words out of the envelope', () {
      final content = MarketingContent.fromJson({
        'document': {'cta.headline': 'Join us'},
      });

      expect(content.text('cta.headline'), 'Join us');
    });

    test('an empty document is the page as it ships', () {
      final content = MarketingContent.fromJson({'document': <String, dynamic>{}});

      expect(content.changed, isEmpty);
      expect(content.text('cta.headline'), marketingDefaults['cta.headline']);
    });

    test('a shape nobody expected is the page as it ships, not a crash', () {
      for (final body in <Map<String, dynamic>>[
        {},
        {'document': null},
        {'document': 'nonsense'},
        {'document': 42},
      ]) {
        expect(MarketingContent.fromJson(body).changed, isEmpty, reason: '$body');
      }
    });

    test('a value that is not a word is ignored rather than rendered', () {
      final content = MarketingContent.fromJson({
        'document': {'hero.headline': 'Fine', 'hero.body': 12, 'cta.button': null},
      });

      expect(content.text('hero.headline'), 'Fine');
      expect(content.text('hero.body'), marketingDefaults['hero.body']);
      expect(content.text('cta.button'), marketingDefaults['cta.button']);
    });
  });

  group('the defaults themselves', () {
    test('every section the page draws has its words', () {
      // A missing key is a blank on the public homepage, so the list is
      // pinned rather than left to whoever edits a widget next.
      for (final key in [
        'nav.wordmark',
        'nav.tagline',
        'nav.login',
        'nav.join',
        'nav.joinShort',
        'hero.eyebrow',
        'hero.headline',
        'hero.body',
        'hero.primaryButton',
        'hero.secondaryButton',
        'hero.trustLine',
        'features.eyebrow',
        'features.title',
        'features.body',
        'mobile.eyebrow',
        'mobile.headline',
        'mobile.body',
        'web.eyebrow',
        'web.headline',
        'web.body',
        'cta.headline',
        'cta.body',
        'cta.button',
        'footer.wordmark',
        'footer.blurb',
        'footer.newsletterTitle',
        'footer.newsletterBody',
        'footer.copyright',
        'footer.tagline',
      ]) {
        expect(marketingDefaults[key], isNotNull, reason: 'no default for $key');
        expect(marketingDefaults[key], isNotEmpty, reason: '$key is empty');
      }
    });

    test('every key is section.field, so the editor can group them', () {
      for (final key in marketingDefaults.keys) {
        expect(key.split('.').length, 2, reason: '$key is not section.field');
      }
    });
  });
}
