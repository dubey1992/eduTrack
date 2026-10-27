import 'package:flutter/services.dart';

/// What the editor's format buttons do to the text box (docs/site-pages.md).
///
/// Each takes the box as it stands - text and selection - and returns it
/// changed, with the cursor or selection where somebody would expect it to
/// be next. Pure, so each can be tested without a screen.

/// The markers a line can start with. Choosing one replaces whichever the
/// line already has, so a bullet turned into a heading does not become
/// "## - Item".
final _linePrefix = RegExp(r'^(#{1,3}\s+|\s*[-*]\s+|\s*\d{1,4}[.)]\s+)');

/// Starts every line the selection touches with [prefix] - or, when they
/// all already start with it, takes it off again, so pressing a button
/// twice undoes it.
///
/// For a numbered list ([prefix] `1. `) the lines are numbered in order.
TextEditingValue applyLinePrefix(TextEditingValue value, String prefix) {
  final text = value.text;
  final selection = _validSelection(value);

  final start = _lineStart(text, selection.start);
  final end = _lineEnd(text, selection.end);
  final lines = text.substring(start, end).split('\n');

  final numbered = prefix == '1. ';
  final hasIt = numbered
      ? lines.every((line) => RegExp(r'^\s*\d{1,4}[.)]\s+').hasMatch(line))
      : lines.every((line) => line.startsWith(prefix));

  var number = 0;
  final changed = [
    for (final line in lines)
      if (hasIt)
        line.replaceFirst(_linePrefix, '')
      else if (line.trim().isEmpty && lines.length > 1)
        // A blank line inside the selection stays a paragraph break rather
        // than becoming an empty bullet.
        line
      else
        '${numbered ? '${++number}. ' : prefix}${line.replaceFirst(_linePrefix, '')}',
  ].join('\n');

  final newText = text.replaceRange(start, end, changed);

  // One line with nothing selected: the cursor goes to the end of that line,
  // ready to keep typing. Otherwise the changed lines stay selected.
  final newSelection = selection.isCollapsed && lines.length == 1
      ? TextSelection.collapsed(offset: start + changed.length)
      : TextSelection(baseOffset: start, extentOffset: start + changed.length);

  return TextEditingValue(text: newText, selection: newSelection);
}

/// Wraps the selection in [marker] (`**` for bold). With nothing selected,
/// puts [placeholder] there inside the markers, selected, so typing replaces
/// it.
TextEditingValue wrapSelection(TextEditingValue value, String marker, String placeholder) {
  final text = value.text;
  final selection = _validSelection(value);
  final selected = selection.textInside(text);

  // Already wrapped: unwrap, so the button reads as on/off.
  if (selected.length > marker.length * 2 && selected.startsWith(marker) && selected.endsWith(marker)) {
    final inner = selected.substring(marker.length, selected.length - marker.length);
    return TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, inner),
      selection: TextSelection(baseOffset: selection.start, extentOffset: selection.start + inner.length),
    );
  }

  final inner = selected.isEmpty ? placeholder : selected;
  final wrapped = '$marker$inner$marker';
  final innerStart = selection.start + marker.length;

  return TextEditingValue(
    text: text.replaceRange(selection.start, selection.end, wrapped),
    selection: TextSelection(baseOffset: innerStart, extentOffset: innerStart + inner.length),
  );
}

/// Replaces the selection with a link. The cursor ends up just after it.
TextEditingValue insertLink(TextEditingValue value, {required String words, required String address}) {
  final selection = _validSelection(value);
  final link = '[${words.replaceAll(']', '')}](${address.trim()})';

  return TextEditingValue(
    text: value.text.replaceRange(selection.start, selection.end, link),
    selection: TextSelection.collapsed(offset: selection.start + link.length),
  );
}

/// A line across the page, on a line of its own with a blank line either
/// side, wherever the cursor is.
TextEditingValue insertDivider(TextEditingValue value) {
  final text = value.text;
  final at = _lineEnd(text, _validSelection(value).end);

  final before = at == 0 ? '' : '\n\n';
  // Mid-text, the line break already after [at] supplies one of the two.
  final after = at < text.length ? '\n' : '\n\n';
  final inserted = '$before---$after';

  return TextEditingValue(
    text: text.replaceRange(at, at, inserted),
    selection: TextSelection.collapsed(offset: at + inserted.length),
  );
}

/// The text that a selection covers, for prefilling the link dialog.
String selectedText(TextEditingValue value) => _validSelection(value).textInside(value.text);

/// A text box nobody has clicked into has a selection of -1; treat that as
/// the end of the text.
TextSelection _validSelection(TextEditingValue value) {
  final selection = value.selection;
  if (selection.isValid) return selection;

  return TextSelection.collapsed(offset: value.text.length);
}

int _lineStart(String text, int offset) => offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

int _lineEnd(String text, int offset) {
  final end = text.indexOf('\n', offset);
  return end == -1 ? text.length : end;
}
