import 'package:edutrack_app/features/marketing/presentation/widgets/marketing_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The marketing bar is the first thing anyone sees, on whatever they own.
///
/// It used to decide whether to show its links from the *window* width, while
/// being laid out inside a width-capped, padded wrapper - so on a middling
/// screen it kept links it had no room for and ran off the edge.
void main() {
  Widget wrap(double width) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: MarketingNavBar(
            onNavigate: {
              'Features': () {},
              'Modules': () {},
              'Pricing': () {},
              'Contact': () {},
            },
            onJoinEarlyAccess: () {},
          ),
        ),
      ),
    );
  }

  for (final width in [360.0, 390.0, 600.0, 800.0, 1024.0, 1440.0]) {
    testWidgets('lays out without overflowing at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(width));
      await tester.pumpAndSettle();

      // An overflow is reported as a framework exception, so reaching here
      // without one is the assertion.
      expect(tester.takeException(), isNull);
      expect(find.text('School365ai'), findsOneWidget);
      // The actions never drop, however narrow it gets - they are the point
      // of the bar.
      expect(find.text('Login'), findsOneWidget);
    });
  }

  testWidgets('drops the section links when there is no room for them', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(390));
    await tester.pumpAndSettle();

    expect(find.text('Features'), findsNothing);
  });

  testWidgets('keeps the section links when there is room', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(1440));
    await tester.pumpAndSettle();

    expect(find.text('Features'), findsOneWidget);
  });
}
