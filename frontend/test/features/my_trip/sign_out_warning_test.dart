import 'dart:convert';

import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/app_shell.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/my_trip/data/models/trip_mark.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';
import '../../support/session_users.dart';

/// Signing out throws away whatever trip marks never reached the server, so
/// an attendant with some waiting is told first (docs/maps.md, "Offline").
void main() {
  late InMemoryKeyValueStore store;
  late FakeMyTripApi api;

  setUp(() {
    store = InMemoryKeyValueStore();
    // No signal: whatever is waiting stays waiting.
    api = FakeMyTripApi()..offline = true;
  });

  void leaveMarksOnThePhone(int count) {
    store.values['my_trip.marks'] = jsonEncode([
      for (var i = 0; i < count; i++)
        TripMark.now(tripId: 55, type: TripMarkType.boarded, label: 'Child $i boarded', studentId: i).toJson(),
    ]);
  }

  Future<FakeAuthRepository> pumpShell(
    WidgetTester tester,
    AuthenticatedUser user, {
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthRepository(sessionOnRestore: user);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          keyValueStoreProvider.overrideWithValue(store),
          myTripApiProvider.overrideWithValue(api),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            initialLocation: '/my-trip',
            routes: [
              ShellRoute(
                builder: (context, state, child) => AppShell(child: child),
                routes: [GoRoute(path: '/my-trip', builder: (context, state) => const Text('The trip'))],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  final attendant = sessionUser(UserRole.busAttendant);

  testWidgets('an attendant with marks waiting is told they will be lost', (tester) async {
    leaveMarksOnThePhone(6);
    await pumpShell(tester, attendant);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('6 marks have not been sent yet. Sign out anyway? They will be lost.'), findsOneWidget);
  });

  testWidgets('staying signed in keeps the marks', (tester) async {
    leaveMarksOnThePhone(2);
    final auth = await pumpShell(tester, attendant);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay signed in'));
    await tester.pumpAndSettle();

    expect(auth.loggedOutCalled, isFalse);
    expect(jsonDecode(store.values['my_trip.marks']!), hasLength(2));
  });

  testWidgets('signing out anyway forgets the marks and the saved trip', (tester) async {
    leaveMarksOnThePhone(1);
    store.values['my_trip.routes'] = jsonEncode(myRoutesJson());
    final auth = await pumpShell(tester, attendant);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('1 mark has not been sent yet. Sign out anyway? They will be lost.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(auth.loggedOutCalled, isTrue);
    expect(store.values.keys.where((key) => key.startsWith('my_trip.')), isEmpty);
  });

  testWidgets('with nothing waiting, the ordinary question', (tester) async {
    await pumpShell(tester, attendant);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('You will need to sign in again to get back to your school.'), findsOneWidget);
  });

  testWidgets('on a phone, Log out is in the app bar', (tester) async {
    leaveMarksOnThePhone(3);
    await pumpShell(tester, attendant, size: const Size(400, 800));

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('3 marks have not been sent yet. Sign out anyway? They will be lost.'), findsOneWidget);
  });
}
