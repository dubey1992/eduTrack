import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/data/map_navigator.dart';
import 'package:edutrack_app/features/my_trip/data/navigation_session.dart';
import 'package:edutrack_app/features/my_trip/presentation/navigate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/my_trip_fixtures.dart';

/// Guidance inside the app, and what happens on the morning it refuses
/// (docs/driver-app.md, D7).
///
/// The point of nearly every test here is the fallback: a driver whose key
/// has no Navigation SDK, or who declines Google's terms, still has to
/// reach the stop. The Google Maps hand-off from D5.1 is what catches them.
void main() {
  late FakeNavigationSession session;
  late FakeMapNavigator navigator;

  setUp(() {
    session = FakeNavigationSession(supported: true);
    navigator = FakeMapNavigator();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          navigationSessionProvider.overrideWithValue(session),
          mapNavigatorProvider.overrideWithValue(navigator),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NavigateScreen(
            destination: NavigateTo(latitude: 12.9716, longitude: 77.5946, stopName: 'Main Gate'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('guides to the stop it was given', (tester) async {
    await pumpScreen(tester);

    expect(session.guidedTo, ['Main Gate:12.9716,77.5946']);
    expect(find.byKey(const Key('nav-view')), findsOneWidget);
  });

  testWidgets('a key without the Navigation SDK says so and offers Google Maps', (tester) async {
    session.outcome = NavigationOutcome.unavailable;
    await pumpScreen(tester);

    expect(find.byKey(const Key('nav-unavailable')), findsOneWidget);
    expect(find.textContaining('not switched on for your school yet'), findsOneWidget);
    expect(find.byKey(const Key('nav-view')), findsNothing);
  });

  testWidgets("and that button really does hand the stop over", (tester) async {
    session.outcome = NavigationOutcome.unavailable;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('nav-hand-off')));
    await tester.pumpAndSettle();

    expect(navigator.destinations, [(12.9716, 77.5946)]);
  });

  testWidgets('a driver who declines Google\'s terms is not stranded', (tester) async {
    session.outcome = NavigationOutcome.termsRefused;
    await pumpScreen(tester);

    expect(find.byKey(const Key('nav-terms-refused')), findsOneWidget);
    expect(find.byKey(const Key('nav-hand-off')), findsOneWidget);
  });

  testWidgets('no route reads as no route, not as something being switched off', (tester) async {
    session.outcome = NavigationOutcome.noRoute;
    await pumpScreen(tester);

    expect(find.byKey(const Key('nav-no-route')), findsOneWidget);
    expect(find.textContaining('Check your signal'), findsOneWidget);
  });

  testWidgets('a phone with no maps app at all is told rather than left guessing', (tester) async {
    session.outcome = NavigationOutcome.unavailable;
    navigator.opens = false;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('nav-hand-off')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open a maps app on this phone.'), findsOneWidget);
  });

  testWidgets('leaving the screen closes the session, so guidance does not outlive it', (tester) async {
    await pumpScreen(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(session.stops, 1);
  });
}
