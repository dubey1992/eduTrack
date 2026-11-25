import 'package:edutrack_app/core/l10n/l10n.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/data/battery_guard.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/map_navigator.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/navigation_session.dart';
import 'package:edutrack_app/features/my_trip/data/phone_dialer.dart';
import 'package:edutrack_app/features/my_trip/data/trip_service.dart';
import 'package:edutrack_app/features/my_trip/data/voice_search.dart';
import 'package:edutrack_app/features/my_trip/presentation/my_trip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_key_value_store.dart';
import '../support/my_trip_fixtures.dart';
import 'a11y_audit.dart';

/// Large text and screen readers in the Bus app (docs/mobile-apps-review.md,
/// M11, 3.4): the routes list and a running trip, in English and Hindi, at
/// normal and double text size, on a phone-sized screen.
void main() {
  for (final locale in const [Locale('en'), Locale('hi')]) {
    for (final scale in [1.0, 2.0]) {
      for (final running in [false, true]) {
        testWidgets('bus ${running ? 'running trip' : 'routes'} in ${locale.languageCode} at ${scale}x', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final handle = tester.ensureSemantics();
          final audit = A11yAudit(tester)..watchLayout();

          final api = FakeMyTripApi();
          if (running) api.routes = myRoutesJson(pickup: api.serverTrip);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                myTripApiProvider.overrideWithValue(api),
                keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
                locationSourceProvider.overrideWithValue(FakeLocationSource(access: LocationAccess.denied)),
                tripServiceProvider.overrideWithValue(FakeTripService()),
                phoneDialerProvider.overrideWithValue(FakePhoneDialer()),
                mapNavigatorProvider.overrideWithValue(FakeMapNavigator()),
                batteryGuardProvider.overrideWithValue(FakeBatteryGuard()),
                navigationSessionProvider.overrideWithValue(FakeNavigationSession()),
                voiceSearchProvider.overrideWithValue(FakeVoiceSearch()),
              ],
              child: MaterialApp(
                theme: AppTheme.crewLight(),
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const Scaffold(body: MyTripScreen()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (running) {
            await tester.tap(find.byKey(const Key('continue-pickup')));
            await tester.pumpAndSettle();
          }

          expect(await audit.checkScrolling(), isEmpty);
          handle.dispose();
        });
      }
    }
  }
}
