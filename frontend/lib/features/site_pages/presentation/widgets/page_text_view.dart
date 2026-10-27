import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../marketing/data/marketing_links.dart';
import '../../data/page_text.dart';

/// Draws page text (see [parsePageText]) - on the public page, and in the
/// editor's preview, which is the same widget so the two cannot disagree.
///
/// A link is followed under the same rules as a homepage footer line: an
/// address the footer would refuse is drawn as the plain words, never as
/// something that can be clicked.
class PageTextView extends StatefulWidget {
  const PageTextView({super.key, required this.text, this.followLinks = true});

  final String text;

  /// False in the editor's preview: a click there should not take the Super
  /// Admin away from what they are writing. The links still look like links.
  final bool followLinks;

  @override
  State<PageTextView> createState() => _PageTextViewState();
}

class _PageTextViewState extends State<PageTextView> {
  /// Made afresh on every build and disposed with the previous set, so a
  /// page that is being typed into does not leak one per keystroke.
  List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers(_recognizers);
    super.dispose();
  }

  void _disposeRecognizers(List<TapGestureRecognizer> recognizers) {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final previous = _recognizers;
    _recognizers = [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _disposeRecognizers(previous));

    final theme = Theme.of(context);
    const body = TextStyle(fontSize: 15, height: 1.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in parsePageText(widget.text))
          switch (block) {
            PageHeading(:final level, :final spans) => Padding(
              padding: EdgeInsets.only(top: level == 1 ? 28 : 22, bottom: 8),
              child: Text.rich(
                _spans(spans),
                style: switch (level) {
                  1 => theme.textTheme.headlineSmall,
                  2 => theme.textTheme.titleLarge,
                  _ => theme.textTheme.titleMedium,
                }?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            PageParagraph(:final spans) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text.rich(_spans(spans), style: body),
            ),
            PageListItem(:final spans, :final number) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: number == null
                        ? const Padding(
                            padding: EdgeInsets.only(top: 9),
                            child: Align(alignment: Alignment.topLeft, child: Icon(Icons.circle, size: 7)),
                          )
                        : Text('$number.', style: body),
                  ),
                  Expanded(child: Text.rich(_spans(spans), style: body)),
                ],
              ),
            ),
            PageDivider() => const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
          },
      ],
    );
  }

  TextSpan _spans(List<PageSpan> spans) {
    final linkColor = Theme.of(context).colorScheme.primary;

    return TextSpan(
      children: [
        for (final span in spans)
          if (span.link != null && linkKind(span.link) != null)
            TextSpan(
              text: span.text,
              style: TextStyle(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor),
              mouseCursor: widget.followLinks ? SystemMouseCursors.click : MouseCursor.defer,
              recognizer: widget.followLinks ? _recognizerFor(span.link!) : null,
            )
          else
            TextSpan(
              text: span.text,
              style: span.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
            ),
      ],
    );
  }

  TapGestureRecognizer _recognizerFor(String address) {
    final recognizer = TapGestureRecognizer()..onTap = () => followMarketingLink(context, address);
    _recognizers.add(recognizer);

    return recognizer;
  }
}
