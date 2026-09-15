import 'package:edutrack_app/features/marketing/presentation/widgets/marketing_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The marketing bar is the first thing anyone sees, on whatever they own.
///
/// It used to decide whether to show its links from the *window* width, while
/// being laid out inside a width-capped, padded wrapper - so on a middling
/// screen it kept links it had no room for and ran off the edge.
void main() {
  const labels = ['Features', 'Modules', 'Pricing', 'Contact'];

  Widget wrap(double width, {List<String> links = labels}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: MarketingNavBar(
            onNavigate: {for (final label in links) label: () {}},
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

    // A short set on purpose. The suite's font is far wider than the one the
    // site loads, so "a wide bar" is not by itself enough room for five real
    // labels here - and asserting that it is would only be asserting the
    // clipping this test file exists to prevent.
    await tester.pumpWidget(wrap(1440, links: ['Features', 'Contact']));
    await tester.pumpAndSettle();

    expect(find.text('Features'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
  });

  /// The links are shown whole or not at all. They used to scroll inside
  /// whatever space was left, which meant that on a bar with too little of it
  /// the first link arrived cut down the middle and sitting under the brand -
  /// which reads as a broken page, not as something to scroll.
  for (final width in [960.0, 1024.0, 1238.0, 1440.0, 1920.0]) {
    testWidgets('never shows a half-cut link at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(width));
      await tester.pumpAndSettle();

      final links = find.text('Features');
      if (links.evaluate().isEmpty) return; // dropped whole: nothing to cut

      // Shown means shown in full. Every label, inside the bar, uncut - and
      // clear of the brand it sat on top of and the actions it ran into.
      final bar = tester.getRect(find.byType(MarketingNavBar));
      final brand = tester.getRect(find.text('School365ai'));
      final login = tester.getRect(find.text('Login'));

      for (final label in labels) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(bar.left), reason: '$label is cut off on the left');
        expect(rect.right, lessThanOrEqualTo(bar.right), reason: '$label is cut off on the right');
        expect(rect.left, greaterThanOrEqualTo(brand.right), reason: '$label overlaps the brand');
        expect(rect.right, lessThanOrEqualTo(login.left), reason: '$label overlaps the Login button');
      }
    });
  }
}
