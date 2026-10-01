import 'marketing_defaults.dart';

/// The homepage's words: what the Super Admin changed, over what ships.
///
/// Every lookup falls back to [marketingDefaults], so a missing key, an
/// empty override, a failed request and a backend that is down all render
/// the page exactly as it ships (docs/marketing-content.md).
class MarketingContent {
  const MarketingContent(this.changed);

  /// Nothing changed - the page as it ships. What the screen shows while
  /// the request is in flight, and if it never comes back.
  const MarketingContent.asItShips() : changed = const {};

  factory MarketingContent.fromJson(Map<String, dynamic> json) {
    final document = json['document'];

    if (document is! Map) return const MarketingContent.asItShips();

    return MarketingContent({
      for (final entry in document.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    });
  }

  /// Only the overrides. A key absent here means "as it ships", which is
  /// different from a key set to an empty string - and both read the same
  /// way out of [text], because a blank headline helps nobody.
  final Map<String, String> changed;

  String text(String key) {
    final override = changed[key];

    if (override != null && override.trim().isNotEmpty) return override;

    // A key with no default is a typo at the call site rather than
    // something a reader should ever see, so it is loud in debug and
    // harmless in release.
    assert(marketingDefaults.containsKey(key), 'No marketing default for "$key"');

    return marketingDefaults[key] ?? '';
  }
}
