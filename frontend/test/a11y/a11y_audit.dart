import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a screen breaks for people who read with large text or a screen
/// reader (docs/mobile-apps-review.md, M11, 3.4): layout overflow at the
/// given text size, tappable things with nothing to say, and tap targets
/// under Android's 48 x 48.
///
/// Read-only selectable text (a UPI ID, office hours) is left out of the
/// tap-size rule: it is text to copy, not a button.
class A11yAudit {
  A11yAudit(this.tester);

  final WidgetTester tester;
  final List<String> problems = [];

  /// Kept for the callers' sake; nothing to set up. Layout errors are read
  /// from the test after each check (see [_takeLayoutError]) rather than by
  /// replacing FlutterError.onError, which the test binding needs for itself.
  void watchLayout() {}

  /// The error the test is holding, as a finding when it is an overflow.
  ///
  /// google_fonts cannot download under flutter test (every request gets a
  /// 400) and reports that late; that is not the screen's problem.
  void _takeLayoutError() {
    final error = tester.takeException();
    if (error == null) return;
    final message = error.toString();
    if (message.contains('Failed to load font') || message.contains('google_fonts')) return;
    final firstLine = message.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => message);
    final where = RegExp(r'(lib/[^\s:]+\.dart:\d+)').firstMatch(message)?.group(1);
    problems.add('layout: ${firstLine.trim()}${where == null ? '' : ' at $where'}');
  }

  /// Checks the screen as it opens, then each page further down its main
  /// list, so what is below the fold is checked too.
  Future<List<String>> checkScrolling() async {
    await check();
    final lists = find.byType(Scrollable);
    for (var page = 0; page < 6 && tester.any(lists); page++) {
      final list = lists.first;
      final before = tester.state<ScrollableState>(list).position.pixels;
      await tester.drag(list, const Offset(0, -600), warnIfMissed: false);
      // Fixed waits, not pumpAndSettle: a screen with a spinner never settles.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (tester.state<ScrollableState>(list).position.pixels == before) break;
      await check();
    }
    return problems.toSet().toList();
  }

  Future<List<String>> check() async {
    _takeLayoutError();
    for (final (name, guideline) in [('label', labeledTapTargetGuideline), ('tap size', androidTapTargetGuideline)]) {
      final result = await guideline.evaluate(tester);
      if (result.passed) continue;
      for (final line in (result.reason ?? '').split('\n')) {
        final text = line.trim();
        if (!text.startsWith('SemanticsNode')) continue;
        if (text.contains('isTextField') && text.contains('isReadOnly')) continue;
        final label = RegExp(r'label: "([^"]*)"').firstMatch(text)?.group(1);
        final value = RegExp(r'value: "([^"]*)"').firstMatch(text)?.group(1);
        final size = RegExp(r'expected tap target size of at least Size\([^)]*\), but found (Size\([^)]*\))')
            .firstMatch(text)
            ?.group(1);
        // A target a few pixels across is one the list has scrolled almost
        // out of view, measured by its visible sliver - no real control is
        // under 12 px, so such a reading is the scroll, not the screen.
        final sides = RegExp(r'Size\(([\d.]+), ([\d.]+)\)').firstMatch(size ?? '');
        if (sides != null && (double.parse(sides.group(1)!) < 12 || double.parse(sides.group(2)!) < 12)) continue;
        problems.add('$name: ${label ?? value ?? '(no label)'}${size == null ? '' : ' $size'}');
      }
    }
    return problems.toSet().toList();
  }
}
