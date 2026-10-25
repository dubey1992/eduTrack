import 'package:edutrack_app/core/widgets/teacher_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Teacher app's mark (core/widgets/teacher_mark.dart).
void main() {
  Future<void> show(WidgetTester tester, Widget mark) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: mark)),
      ),
    );
  }

  testWidgets('takes exactly the size it is given, with or without its tile', (tester) async {
    await show(tester, const TeacherMark(key: Key('plain'), size: 48));
    expect(tester.getSize(find.byKey(const Key('plain'))), const Size(48, 48));

    await show(tester, const TeacherMark(key: Key('tile'), size: 96, tile: true));
    expect(tester.getSize(find.byKey(const Key('tile'))), const Size(96, 96));
  });

  testWidgets('paints shut, half open and open without complaint, and past either end', (tester) async {
    for (final openness in [-1.0, 0.0, 0.5, 1.0, 2.0]) {
      await show(tester, TeacherMark(size: 120, openness: openness));
      expect(tester.takeException(), isNull, reason: 'openness $openness');
    }
  });

  testWidgets('is decoration to a screen reader: the name beside it says it in words', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, const TeacherMark(size: 64, tile: true));

    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    semantics.dispose();
  });
}
