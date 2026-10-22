import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/presentation/driver_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The screen the bus crew opens on (docs/driver-app.md).
///
/// The web app's splash is a bare spinner, which is right for something
/// nobody watches for more than a frame. This one is watched - a phone in a
/// yard, sometimes on a network that is barely there - so what it says
/// while it waits, and what it offers when the wait goes on, are the whole
/// point of it.
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: DriverSplashScreen())));
  }

  testWidgets('says what it is doing rather than only spinning', (tester) async {
    await pump(tester);

    expect(find.text('Getting your trips ready…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('splash-try-again')), findsNothing);
  });

  testWidgets('carries the shuttle running its route', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('splash-animation')), findsOneWidget);
  });

  testWidgets('a wait that goes on offers the only useful thing', (tester) async {
    // Six seconds on a bare spinner is indistinguishable from a broken app,
    // and the crew cannot tell a slow morning from one.
    await pump(tester);

    await tester.pump(const Duration(seconds: 6));

    expect(find.text('Still trying to reach your school.'), findsOneWidget);
    expect(find.byKey(const Key('splash-try-again')), findsOneWidget);
    expect(find.textContaining('signal'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('and trying again goes back to waiting', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.byKey(const Key('splash-try-again')));
    await tester.pump();

    expect(find.text('Getting your trips ready…'), findsOneWidget);
    expect(find.byKey(const Key('splash-try-again')), findsNothing);
  });

  testWidgets('an ordinary cold start never shows the button', (tester) async {
    await pump(tester);

    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('splash-try-again')), findsNothing);
  });

  testWidgets('it fits a small phone in the app theme', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.light(), home: const DriverSplashScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 6));

    expect(tester.takeException(), isNull);
  });
}
