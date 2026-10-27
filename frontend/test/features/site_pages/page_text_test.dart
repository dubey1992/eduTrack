import 'package:edutrack_app/features/site_pages/data/page_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edutrack_app/features/site_pages/presentation/page_text_editing.dart';

/// The page-text format and the format buttons (docs/site-pages.md).
void main() {
  group('reading page text', () {
    test('headings, paragraphs, lists and a divider each become their own block', () {
      final blocks = parsePageText(
        '# Title\n'
        '## Section\n'
        '### Smaller\n'
        'A paragraph.\n'
        '\n'
        '- one\n'
        '* two\n'
        '1. first\n'
        '2) second\n'
        '---\n'
        'After the line.',
      );

      expect(blocks.map((b) => b.runtimeType.toString()).toList(), [
        'PageHeading',
        'PageHeading',
        'PageHeading',
        'PageParagraph',
        'PageListItem',
        'PageListItem',
        'PageListItem',
        'PageListItem',
        'PageDivider',
        'PageParagraph',
      ]);
      expect([for (final b in blocks.whereType<PageHeading>()) b.level], [1, 2, 3]);
      expect([for (final b in blocks.whereType<PageListItem>()) b.number], [null, null, 1, 2]);
    });

    test('a single line break stays inside the paragraph; a blank line starts a new one', () {
      final blocks = parsePageText('Line one\nLine two\n\nNext paragraph');

      expect(blocks, hasLength(2));
      expect((blocks.first as PageParagraph).spans.single.text, 'Line one\nLine two');
    });

    test('Windows line endings read the same', () {
      expect(parsePageText('# Title\r\n\r\nBody'), hasLength(2));
    });

    test('bold at the start of a line is not mistaken for a bullet', () {
      final blocks = parsePageText('**Drivers:** do not use the app while moving.');

      expect(blocks.single, isA<PageParagraph>());
      expect((blocks.single as PageParagraph).spans.first, const PageSpan('Drivers:', bold: true));
    });

    test('bold and links inside a line', () {
      expect(parseInline('Read our **Privacy Policy** at [this page](/privacy) today.'), const [
        PageSpan('Read our '),
        PageSpan('Privacy Policy', bold: true),
        PageSpan(' at '),
        PageSpan('this page', link: '/privacy'),
        PageSpan(' today.'),
      ]);
    });

    test('markup that is not part of the format is the characters somebody typed', () {
      final spans = parseInline('<script>alert(1)</script> and [unfinished](link');

      expect(spans.single.text, '<script>alert(1)</script> and [unfinished](link');
      expect(spans.single.link, isNull);
    });

    test('a link whose address is not one the page will follow is still parsed - the renderer decides', () {
      expect(parseInline('[click](javascript:alert(1))').first.link, 'javascript:alert(1');
    });

    test('an empty page is no blocks at all', () {
      expect(parsePageText('\n\n  \n'), isEmpty);
    });
  });

  group('the format buttons', () {
    TextEditingValue box(String text, int start, [int? end]) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
    );

    test('Heading starts the line the cursor is on', () {
      final changed = applyLinePrefix(box('Intro\nYour account\nMore', 8), '## ');

      expect(changed.text, 'Intro\n## Your account\nMore');
      expect(changed.selection.baseOffset, 'Intro\n## Your account'.length);
    });

    test('pressing it again takes it off', () {
      expect(applyLinePrefix(box('## Your account', 3), '## ').text, 'Your account');
    });

    test('a different marker replaces the one already there', () {
      expect(applyLinePrefix(box('- Item', 2), '## ').text, '## Item');
    });

    test('a bullet list covers every selected line, leaving blank lines alone', () {
      final text = 'one\n\ntwo';

      expect(applyLinePrefix(box(text, 0, text.length), '- ').text, '- one\n\n- two');
    });

    test('a numbered list counts the lines in order', () {
      final text = 'a\nb\nc';

      expect(applyLinePrefix(box(text, 0, text.length), '1. ').text, '1. a\n2. b\n3. c');
    });

    test('a box nobody has clicked into still works, at the end', () {
      const value = TextEditingValue(text: 'Hello');

      expect(applyLinePrefix(value, '- ').text, '- Hello');
    });

    test('Bold wraps the selection, and selects the words inside', () {
      final changed = wrapSelection(box('make this bold', 5, 9), '**', 'bold text');

      expect(changed.text, 'make **this** bold');
      expect(changed.selection.textInside(changed.text), 'this');
    });

    test('Bold with nothing selected puts placeholder words in, selected to type over', () {
      final changed = wrapSelection(box('', 0), '**', 'bold text');

      expect(changed.text, '**bold text**');
      expect(changed.selection.textInside(changed.text), 'bold text');
    });

    test('Bold on words that are already bold takes it off', () {
      expect(wrapSelection(box('**this**', 0, 8), '**', 'bold text').text, 'this');
    });

    test('a link replaces the selection', () {
      final changed = insertLink(box('see here now', 4, 8), words: 'here', address: ' /privacy ');

      expect(changed.text, 'see [here](/privacy) now');
      expect(changed.selection.baseOffset, 'see [here](/privacy)'.length);
    });

    test('a divider goes on a line of its own', () {
      expect(insertDivider(box('Para one\nstill one', 2)).text, 'Para one\n\n---\n\nstill one');
      expect(insertDivider(box('', 0)).text, '---\n\n');
    });
  });
}
