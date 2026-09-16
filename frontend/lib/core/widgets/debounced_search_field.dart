import 'dart:async';

import 'package:flutter/material.dart';

/// A search box that waits for the typing to stop before it asks the server.
///
/// Wired straight to `onChanged`, a search box sends a request per keystroke:
/// "Abhishek" is eight of them, seven of which are for a prefix nobody wanted,
/// and their replies can arrive in any order - so the list can settle on the
/// answer to "Abhi" after the answer to "Abhishek" has already been drawn.
///
/// So the callback fires once the field has been quiet for [delay], and at
/// once on Enter or on clearing - both of which are the user saying they have
/// finished. Screens that filter a list they already hold in memory do not
/// need this; the ones that fetch do.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.label,
    this.delay = const Duration(milliseconds: 400),
  });

  final TextEditingController controller;

  /// Given the trimmed text. Called once per settled change, never for a
  /// value it has already been given.
  final ValueChanged<String> onSearch;

  final String label;

  /// Long enough to cover the gap between keystrokes, short enough that the
  /// results feel like they are keeping up.
  final Duration delay;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  Timer? _timer;

  /// What the parent was last told. Typing a letter and deleting it again
  /// leaves the search where it was, so there is nothing to say.
  String _dispatched = '';

  @override
  void initState() {
    super.initState();
    _dispatched = widget.controller.text.trim();
  }

  @override
  void dispose() {
    // Without this a request can be fired at a notifier whose screen has
    // gone, from a timer belonging to a widget that no longer exists.
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.delay, _dispatch);
    // Redraws for the clear button, which appears with the first character.
    setState(() {});
  }

  void _dispatch() {
    _timer?.cancel();

    final value = widget.controller.text.trim();
    if (value == _dispatched) return;

    _dispatched = value;
    widget.onSearch(value);
  }

  void _clear() {
    widget.controller.clear();
    _dispatch();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close, size: 18), onPressed: _clear),
      ),
      onChanged: (_) => _schedule(),
      // Enter means "now", not "in four hundred milliseconds".
      onSubmitted: (_) => _dispatch(),
    );
  }
}
