import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'marketing_screen_test.dart' show wrap;

/// The homepage at the size a browser actually gives it.
///
/// Every other test here uses a viewport 1400 to 4000 pixels tall, so the
/// whole page fits and nothing is ever laid out under pressure. A real
/// window is about 900, and a release build logs "RenderBox was not laid
/// out" on it - so the sizes the tests chose for convenience were hiding
/// something.
/// The part of an exception that names the problem, without the essay
/// of layout advice Flutter appends to an overflow.
String summarise(Object error) {
  final text = error.toString();
  final stop = text.indexOf(String.fromCharCode(10));
  return stop < 0 ? text : text.substring(0, stop);
}

void main() {
  for (final size in [const Size(1440, 900), const Size(1280, 800), const Size(390, 844)]) {
    testWidgets('lays out at ${size.width.toInt()}x${size.height.toInt()} without throwing', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // Drained one at a time: takeException returns only the first, and
      // the page threw four at this size when this was written.
      final thrown = <Object>[];
      for (var error = tester.takeException(); error != null; error = tester.takeException()) {
        thrown.add(error);
      }

      expect(thrown, isEmpty, reason: thrown.map(summarise).join('  ||  '));
    });
  }
}
