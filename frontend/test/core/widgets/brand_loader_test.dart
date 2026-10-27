import 'package:edutrack_app/core/widgets/async_value_view.dart';
import 'package:edutrack_app/core/widgets/brand_loader.dart';
import 'package:edutrack_app/core/widgets/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The School365ai loader, which stands in for a spinning circle wherever a
/// screen or section waits.
void main() {
  testWidgets('tells a screen reader it is loading', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BrandLoader())),
      ),
    );

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('keeps moving while it waits', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BrandLoader())),
      ),
    );

    // A frame later there is still a frame to draw: the hop never settles.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('stands still for somebody who asked their device for less motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: Center(child: BrandLoader())),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the splash screen carries the name under the mark', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(BrandLoader), findsOneWidget);
    expect(find.text('School365ai'), findsOneWidget);
  });

  testWidgets('every screen that waits through AsyncValueView waits with it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncValueView<int>(value: const AsyncLoading(), data: (context, value) => Text('$value')),
        ),
      ),
    );

    expect(find.byType(BrandLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('fits a small space without overflowing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 40, height: 60, child: BrandLoader(size: 36))),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
