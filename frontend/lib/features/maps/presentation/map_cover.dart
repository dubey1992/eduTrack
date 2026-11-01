import 'package:flutter/widgets.dart';

/// Whether something is open over the app's pages: a dialog, a menu, a
/// bottom sheet.
///
/// On the web a map is a browser element underneath Flutter's own drawing,
/// so a click on a dialog's button above it reaches the map too. A map
/// asks this before acting on a click. It watches the app's top navigator,
/// because the pages sit in a navigator of their own inside it and never
/// stop being "current" there while a dialog is open over them.
class MapCover extends NavigatorObserver {
  MapCover._();

  static final instance = MapCover._();

  /// How long after something closes a click still counts as meant for it:
  /// the browser's click reaches the map a moment after the dialog has gone.
  static const settle = Duration(milliseconds: 700);

  final List<Route<dynamic>> _open = [];
  DateTime _closedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True when a click on a map on [mine] (the page or dialog the map is in)
  /// was probably meant for something drawn over it.
  bool covers(Route<dynamic>? mine) {
    if (_open.isNotEmpty && !identical(_open.last, mine)) return true;

    return DateTime.now().difference(_closedAt) < settle;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _open.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _closed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _closed(route);

  void _closed(Route<dynamic> route) {
    if (route is! PopupRoute) return;

    _open.remove(route);
    _closedAt = DateTime.now();
  }
}
