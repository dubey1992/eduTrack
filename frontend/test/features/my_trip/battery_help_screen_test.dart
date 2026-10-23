import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/data/battery_guard.dart';
import 'package:edutrack_app/features/my_trip/presentation/battery_help_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/my_trip_fixtures.dart';

/// The screen a driver is sent to when their phone would otherwise kill the
/// trip's foreground service (docs/driver-app.md, D4.4).
void main() {
  late FakeBatteryGuard battery;

  setUp(() => battery = FakeBatteryGuard(exempt: false));

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [batteryGuardProvider.overrideWithValue(battery)],
        child: MaterialApp(theme: AppTheme.light(), home: const BatteryHelpScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers the one setting Android will let an app ask for', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('allow-background')));
    await tester.pumpAndSettle();

    expect(battery.timesAsked, 1);
    expect(find.textContaining('keep reporting with the screen off'), findsOneWidget);
  });

  testWidgets('a refusal is not the end of it - the steps still do the job', (tester) async {
    battery.grantsWhenAsked = false;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('allow-background')));
    await tester.pumpAndSettle();

    expect(find.textContaining('The steps below do the same thing'), findsOneWidget);
  });

  testWidgets('a phone that already allows it is told so instead of asked again', (tester) async {
    battery.exempt = true;
    await pumpScreen(tester);

    expect(find.byKey(const Key('allow-background')), findsNothing);
    expect(find.text('Already allowed on this phone.'), findsOneWidget);
  });

  testWidgets('carries steps for the makes that actually kill services', (tester) async {
    await pumpScreen(tester);

    for (final make in ['xiaomi, redmi or poco', 'oppo, realme or oneplus', 'vivo or iqoo', 'samsung']) {
      expect(find.byKey(Key('make-$make')), findsOneWidget, reason: '$make is one of the phones drivers carry');
    }
  });

  testWidgets("a make's steps open when it is tapped", (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('make-xiaomi, redmi or poco')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Autostart'), findsWidgets);
  });
}
