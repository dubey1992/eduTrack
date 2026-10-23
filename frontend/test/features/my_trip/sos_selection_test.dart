import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/presentation/widgets/sos_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The SOS button inside the SelectionArea the app actually wraps every
/// screen in (main_driver.dart, main.dart).
///
/// Without that wrapper a widget test is not testing the app: the button
/// passed every test in my_trip_screen_test.dart and still did nothing on a
/// phone, because SelectionArea claimed the long press, highlighted the
/// label and opened a Copy bar. A held button and a selectable label want
/// the same gesture, and the text has to lose (docs/driver-app.md, D5.2).
void main() {
  Future<int> holdAndCount(WidgetTester tester, {required Duration held}) async {
    var sent = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SelectionArea(
          child: Scaffold(
            body: Center(child: SosButton(onSos: () async => sent++)),
          ),
        ),
      ),
    );

    final press = await tester.startGesture(tester.getCenter(find.byKey(const Key('sos'))));

    // One frame first, so the hold's ticker starts; only then does time
    // pass. A single big pump leaves the controller at zero, because its
    // clock begins at its first tick, not at the press.
    await tester.pump();
    await tester.pump(held);

    // Released before settling, or pumpAndSettle would run the hold to the
    // end whatever [held] says - which is a test that always passes.
    await press.up();
    await tester.pumpAndSettle();

    return sent;
  }

  testWidgets('a full hold still reaches the school when the screen is selectable', (tester) async {
    // One frame past the hold, because the controller finishes on the frame
    // after its elapsed time reaches the duration - and because no thumb
    // lets go on the exact millisecond.
    const aFrame = Duration(milliseconds: 16);

    expect(await holdAndCount(tester, held: SosButton.hold + aFrame), 1);
  });

  testWidgets('and the label never becomes something to copy instead', (tester) async {
    await holdAndCount(tester, held: SosButton.hold + const Duration(milliseconds: 16));

    // The Copy bar is what a driver saw instead of help being sent.
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('letting go early still sends nothing', (tester) async {
    expect(await holdAndCount(tester, held: const Duration(milliseconds: 900)), 0);
  });
}
