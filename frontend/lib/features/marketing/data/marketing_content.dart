import 'marketing_defaults.dart';

/// The homepage's words: what the Super Admin changed, over what ships.
///
/// Every lookup falls back to [marketingDefaults], so a missing key, an
/// empty override, a failed request and a backend that is down all render
/// the page exactly as it ships (docs/marketing-content.md).
class MarketingContent {
  const MarketingContent(this.changed, [this.changedLists = const {}, this.livePages]);

  /// Nothing changed - the page as it ships. What the screen shows while
  /// the request is in flight, and if it never comes back.
  const MarketingContent.asItShips() : changed = const {}, changedLists = const {}, livePages = null;

  factory MarketingContent.fromJson(Map<String, dynamic> json) {
    final document = json['document'];
    final pages = json['pages'];
    final livePages = pages is List ? pages.whereType<String>().toSet() : null;

    if (document is! Map) return MarketingContent(const {}, const {}, livePages);

    final words = <String, String>{};
    final lists = <String, List<Map<String, String>>>{};

    for (final entry in document.entries) {
      if (entry.key is! String) continue;
      final key = entry.key as String;
      final value = entry.value;

      if (value is String) {
        words[key] = value;
      } else if (value is List) {
        final items = _items(value);
        // A list that arrived mangled is no list at all: better the page
        // draws the one it ships with than a grid with holes in it.
        if (items != null) lists[key] = items;
      }
    }

    return MarketingContent(words, lists, livePages);
  }

  /// Every item must be a map of strings, or the whole list is refused.
  static List<Map<String, String>>? _items(List<dynamic> value) {
    final items = <Map<String, String>>[];

    for (final item in value) {
      if (item is! Map) return null;

      final fields = <String, String>{};

      for (final entry in item.entries) {
        if (entry.key is! String || entry.value is! String) return null;
        fields[entry.key as String] = entry.value as String;
      }

      if (fields.isEmpty) return null;
      items.add(fields);
    }

    return items.isEmpty ? null : items;
  }

  /// Only the overrides. A key absent here means "as it ships", which is
  /// different from a key set to an empty string - and both read the same
  /// way out of [text], because a blank headline helps nobody.
  final Map<String, String> changed;

  /// The repeating parts somebody changed - the feature cards, the hero
  /// figures, the ticked list, the footer's columns. A key absent here
  /// means the list the page ships with.
  final Map<String, List<Map<String, String>>> changedLists;

  /// The website pages visitors can read (docs/site-pages.md), or null
  /// when the server has not said - and then no link is hidden.
  final Set<String>? livePages;

  /// The addresses that are parts of the homepage or screens of the app,
  /// not website pages - the same words web/.htaccess sends there.
  static const _notPages = {'features', 'for-schools', 'mobile-app', 'contact', 'login', 'forgot-password'};

  static final _word = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// Whether a footer link leads somewhere (docs/seo.md, S1). A link to a
  /// website page nobody has published is a dead end - "page not
  /// available" to a visitor, a broken link to a search engine - so it is
  /// left out until the page goes live. Every other link is kept.
  bool leadsSomewhere(String? url) {
    final pages = livePages;
    if (pages == null || url == null) return true;

    final address = url.trim();
    final uri = Uri.tryParse(address);
    if (uri == null) return true;

    final ours = address.startsWith('/') || uri.host == 'school365ai.com' || uri.host == 'www.school365ai.com';
    if (!ours || uri.hasQuery || uri.hasFragment) return true;

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length != 1) return true;

    final word = segments.single;
    if (_notPages.contains(word) || !_word.hasMatch(word)) return true;

    return pages.contains(word);
  }

  /// A footer column's links, without the ones that lead nowhere.
  List<Map<String, String>> linksThatLead(String key) => [
    for (final link in list(key))
      if (leadsSomewhere(link['url'])) link,
  ];

  /// One repeating list, falling back to the one that ships.
  ///
  /// An empty list reads as "not changed" for the same reason an empty
  /// string does: a hero with no figures under it, or a grid with no
  /// cards, is a hole in the page rather than a choice anybody made here.
  List<Map<String, String>> list(String key) {
    final override = changedLists[key];

    if (override != null && override.isNotEmpty) return override;

    assert(marketingListDefaults.containsKey(key), 'No marketing list default for "$key"');

    return marketingListDefaults[key] ?? const [];
  }

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
