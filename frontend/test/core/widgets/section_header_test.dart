import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header every list screen shares.
///
/// On a phone the title and its actions cannot fit on one line, so they wrap.
/// These check that wrapping does not put two controls on top of each other -
/// which is exactly what happened on fourteen screens when the action row had
/// horizontal spacing but no run spacing.
void main() {
  Widget wrap({required double width, required List<Widget> actions}) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SectionHeader(title: 'Student Management', actions: actions),
        ),
      ),
    );
  }

  List<Widget> actions() => [
    FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add, size: 18), label: const Text('Add Student')),
    const SizedBox(
      width: 220,
      child: TextField(decoration: InputDecoration(labelText: 'Filter by school', isDense: true)),
    ),
  ];

  testWidgets('the action controls never overlap on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(width: 390, actions: actions()));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(FilledButton));
    final field = tester.getRect(find.byType(TextField));

    // They are on separate lines at this width, so the button must finish
    // before the field's box begins. Strictly before: flush rows are the bug
    // this guards - the field's floating label is drawn at the very top of
    // its rect and collides with whatever sits immediately above.
    expect(field.top, greaterThan(button.bottom), reason: 'the filter is drawn under the button');
  });

  testWidgets('a wrapped action row still leaves a gap between the lines', (tester) async {
    await tester.pumpWidget(wrap(width: 390, actions: actions()));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(FilledButton));
    final field = tester.getRect(find.byType(TextField));

    expect(field.top - button.bottom, greaterThan(0));
  });

  testWidgets('both actions stay on one line when there is room', (tester) async {
    await tester.pumpWidget(wrap(width: 1400, actions: actions()));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(FilledButton));
    final field = tester.getRect(find.byType(TextField));

    // Desktop keeps the prototype's single-row header.
    expect(button.top, closeTo(field.top, field.height));
    expect(field.left, greaterThan(button.right));
  });

  testWidgets('nothing is pushed outside the available width', (tester) async {
    await tester.pumpWidget(wrap(width: 390, actions: actions()));
    await tester.pumpAndSettle();

    for (final finder in [find.byType(FilledButton), find.byType(TextField)]) {
      expect(tester.getRect(finder).right, lessThanOrEqualTo(390));
    }
  });
}
