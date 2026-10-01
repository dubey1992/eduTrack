import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/marketing_content.dart';
import '../data/marketing_content_repository.dart';
import 'marketing_screen.dart';

/// The homepage, with the words currently in the editor's boxes.
///
/// Not a rendering of its own: the real [MarketingScreen] inside a scope
/// where the content provider answers with the draft instead of the
/// published document. A preview drawn separately would eventually
/// disagree with the page, which is the one thing a preview must not do.
///
/// Full-screen rather than a small dialog because the page is a page -
/// shrinking it into a box would preview a layout nobody will ever see.
Future<void> showMarketingPreview(BuildContext context, MarketingContent content) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (context) => Dialog.fullscreen(
      child: ProviderScope(
        overrides: [marketingContentProvider.overrideWith(() => _PreviewContent(content))],
        child: Column(
          children: [
            _PreviewBar(onClose: () => Navigator.of(context).pop()),
            const Expanded(child: MarketingScreen()),
          ],
        ),
      ),
    ),
  );
}

/// Says plainly that this is not the live page, because everything below
/// it looks exactly like the live page.
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: colors.infoContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.visibility_outlined, size: 18, color: colors.onInfoContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Preview - these words are not published yet.',
                style: TextStyle(color: colors.onInfoContainer),
              ),
            ),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: 'Close preview'),
          ],
        ),
      ),
    );
  }
}

/// Answers with the draft and never asks the server, so the preview shows
/// what is in the boxes rather than what visitors are reading.
class _PreviewContent extends MarketingContentNotifier {
  _PreviewContent(this._content);

  final MarketingContent _content;

  @override
  MarketingContent build() => _content;
}
