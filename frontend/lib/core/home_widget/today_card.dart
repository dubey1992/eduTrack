/// What the home-screen widget shows (docs/mobile-apps-review.md, M10, 6.1).
///
/// A title, up to four short lines and the time it was true. Three states:
/// the person's day; "locked", while the app lock is on, so a class's or a
/// child's details never sit unlocked on the home screen; and "signed out".
/// The widget draws whatever was last saved - it never fetches anything
/// itself - so every card says when it was true.
class TodayCard {
  const TodayCard({required this.title, required this.lines, required this.asOf}) : state = TodayCardState.today;

  /// The app lock is on: no details, only a way in.
  const TodayCard.locked()
    : title = 'School365ai',
      lines = const ['Tap to open'],
      asOf = null,
      state = TodayCardState.locked;

  /// Nobody is signed in on this phone.
  const TodayCard.signedOut()
    : title = 'School365ai',
      lines = const ['Sign in to see your day'],
      asOf = null,
      state = TodayCardState.signedOut;

  /// The most lines the widget has room for.
  static const maxLines = 4;

  final String title;
  final List<String> lines;

  /// "as of 9:40 AM", or null for a card that is not about the day.
  final String? asOf;
  final TodayCardState state;

  /// The values the native widget reads, by key. Every key is written every
  /// time, empty when unused, so a shorter card never shows a stale line.
  Map<String, String> toWidgetData() => {
    'today_state': state.name,
    'today_title': title,
    for (var i = 0; i < maxLines; i++) 'today_line${i + 1}': i < lines.length ? lines[i] : '',
    'today_as_of': asOf ?? '',
  };

  @override
  String toString() => 'TodayCard(${state.name}: $title | ${lines.join(' | ')} | ${asOf ?? ''})';
}

enum TodayCardState { today, locked, signedOut }
