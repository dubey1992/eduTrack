import 'package:edutrack_app/features/marketing/data/marketing_content.dart';
import 'package:edutrack_app/features/marketing/data/marketing_content_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A scope for the public homepage's widgets, pinned to the copy that
/// ships (docs/marketing-content.md).
///
/// The marketing widgets read their words from a provider, so they need a
/// scope. This one hands them a repository that answers without a network
/// and with nothing changed - which is both what a visitor sees on the
/// first frame and what the layout tests are measuring.
Widget marketingScope(Widget child, {MarketingContent content = const MarketingContent.asItShips()}) {
  return ProviderScope(
    overrides: [marketingContentRepositoryProvider.overrideWithValue(_FixedMarketingContent(content))],
    child: child,
  );
}

class _FixedMarketingContent implements MarketingContentRepository {
  _FixedMarketingContent(this._content);

  final MarketingContent _content;

  @override
  Future<MarketingContent> fetch() async => _content;
}
