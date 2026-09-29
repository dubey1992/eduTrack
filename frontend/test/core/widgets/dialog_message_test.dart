import 'package:edutrack_app/core/widgets/confirm_dialog.dart';
import 'package:edutrack_app/core/widgets/dialog_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One long sentence is all it takes: a bare Text lays it out on a single
/// line, and the dialog grows to fit it.
const _long =
    'Each student keeps every past year on record. This cannot be undone from '
    'here: correcting it afterwards means moving those students by hand.';

void main() {
  /// Raises [open] from a wide window, the way a page raises an alert.
  ///
  /// Through showDialog rather than by pumping the dialog on its own: an
  /// AlertDialog stretches its content to whatever width it is handed, so a
  /// bare pump would measure the test's own layout instead of the dialog's.
  Future<void> onAWideScreen(WidgetTester tester, void Function(BuildContext context) open) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => open(context), child: const Text('Open')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a long message wraps instead of stretching across the window', (tester) async {
    // A short title on purpose. An AlertDialog is as wide as its widest
    // part, so a long title would be the thing under test instead.
    await onAWideScreen(
      tester,
      (context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Promote?'), content: DialogMessage(_long)),
      ),
    );

    final message = tester.getSize(find.byType(DialogMessage));

    expect(message.width, lessThanOrEqualTo(DialogMessage.maxWidth));
    expect(message.height, greaterThan(40), reason: 'the message should have wrapped onto several lines');
    expect(find.text(_long), findsOneWidget, reason: 'capping the width must not cost any of the message');
  });

  testWidgets('a short message still makes a small dialog', (tester) async {
    await onAWideScreen(
      tester,
      (context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Deleted'), content: DialogMessage('Deleted.')),
      ),
    );

    expect(
      tester.getSize(find.byType(DialogMessage)).width,
      lessThan(DialogMessage.maxWidth),
      reason: 'the cap is a maximum, not a width every alert is padded out to',
    );
  });

  testWidgets('the shared confirm dialog is capped too', (tester) async {
    await onAWideScreen(
      tester,
      (context) =>
          confirmDialog(context, title: 'Delete this?', message: _long, confirmLabel: 'Delete', isDestructive: true),
    );

    expect(find.text(_long), findsOneWidget);
    expect(tester.getSize(find.byType(DialogMessage)).width, lessThanOrEqualTo(DialogMessage.maxWidth));
  });
}
