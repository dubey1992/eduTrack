/// The text of a website page, read into blocks (docs/site-pages.md).
///
/// A deliberately small piece of Markdown, because the person writing it is
/// a Super Admin pasting a policy out of a document, not a developer:
///
/// ```text
/// # Heading            ## Smaller heading      ### Smallest heading
/// - A bullet           * also a bullet         1. A numbered item
/// ---                  (a line across the page)
/// **bold**             [words](https://...)    a link
/// ```
///
/// A blank line starts a new paragraph. A single line break inside a
/// paragraph stays a line break - somebody who pressed Enter meant it.
///
/// Nothing here is HTML and nothing is ever drawn as HTML: anything that is
/// not one of the above is simply the characters somebody typed.
library;

sealed class PageBlock {
  const PageBlock();
}

class PageHeading extends PageBlock {
  const PageHeading(this.level, this.spans);

  /// 1, 2 or 3 - the number of `#`s.
  final int level;
  final List<PageSpan> spans;
}

class PageParagraph extends PageBlock {
  const PageParagraph(this.spans);

  final List<PageSpan> spans;
}

class PageListItem extends PageBlock {
  const PageListItem(this.spans, {this.number});

  /// The number somebody typed for a numbered item, or null for a bullet.
  final int? number;
  final List<PageSpan> spans;
}

class PageDivider extends PageBlock {
  const PageDivider();
}

/// A run of text inside a block.
class PageSpan {
  const PageSpan(this.text, {this.bold = false, this.link});

  final String text;
  final bool bold;

  /// Where the words go, exactly as typed. Whether it may be followed is
  /// the renderer's question (see linkKind), not the parser's.
  final String? link;

  @override
  bool operator ==(Object other) => other is PageSpan && other.text == text && other.bold == bold && other.link == link;

  @override
  int get hashCode => Object.hash(text, bold, link);

  @override
  String toString() => 'PageSpan($text, bold: $bold, link: $link)';
}

final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,4})[.)]\s+(.*)$');
final _divider = RegExp(r'^\s*-{3,}\s*$');

/// `**bold**` or `[words](address)`.
final _inline = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]*)\)');

List<PageBlock> parsePageText(String text) {
  final blocks = <PageBlock>[];
  final paragraph = <String>[];

  void endParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(PageParagraph(parseInline(paragraph.join('\n'))));
    paragraph.clear();
  }

  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();

    if (line.trim().isEmpty) {
      endParagraph();
      continue;
    }

    // Checked before bullets: "---" would otherwise read as a bullet whose
    // text is "--".
    if (_divider.hasMatch(line)) {
      endParagraph();
      blocks.add(const PageDivider());
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      endParagraph();
      blocks.add(PageHeading(heading.group(1)!.length, parseInline(heading.group(2)!.trim())));
      continue;
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      endParagraph();
      blocks.add(PageListItem(parseInline(bullet.group(1)!.trim())));
      continue;
    }

    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      endParagraph();
      blocks.add(PageListItem(parseInline(numbered.group(2)!.trim()), number: int.parse(numbered.group(1)!)));
      continue;
    }

    paragraph.add(line.trimLeft());
  }

  endParagraph();

  return blocks;
}

/// The bold and linked runs inside one block of text.
List<PageSpan> parseInline(String text) {
  final spans = <PageSpan>[];
  var at = 0;

  for (final match in _inline.allMatches(text)) {
    if (match.start > at) spans.add(PageSpan(text.substring(at, match.start)));

    final bold = match.group(1);
    spans.add(bold != null ? PageSpan(bold, bold: true) : PageSpan(match.group(2)!, link: match.group(3)));

    at = match.end;
  }

  if (at < text.length) spans.add(PageSpan(text.substring(at)));

  return spans;
}
