import 'dart:async';

import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/maintenance_notifier.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/errors/presentation/maintenance_screen.dart';
import 'package:edutrack_app/features/errors/presentation/not_found_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';

const _teacher = AuthenticatedUser(id: 1, name: 'Priya Nair', email: 'priya@example.com', role: UserRole.teacher);

/// A maintenance notifier that answers the recheck however a test needs,
/// without a Dio client behind it.
class _FakeMaintenance extends MaintenanceNotifier {
  _FakeMaintenance({required this.comesBack, this.gate});

  final bool comesBack;

  /// Holds the check open so a test can see the in-flight state. Without one
  /// the answer arrives before the first pump.
  final Completer<void>? gate;

  int rechecks = 0;

  @override
  bool build() => true;

  @override
  Future<bool> recheck() async {
    rechecks++;
    if (gate != null) await gate!.future;
    if (comesBack) state = false;
    return comesBack;
  }
}

void main() {
  // The maintenance override is always present, never conditional: Riverpod
  // refuses to have the number of overrides change between pumps of the same
  // scope, which the layout group below does.
  Widget wrap(Widget screen, {AuthenticatedUser? session, MaintenanceNotifier Function()? maintenance}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: session)),
        maintenanceProvider.overrideWith(maintenance ?? () => _FakeMaintenance(comesBack: false)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/here',
          routes: [
            GoRoute(path: '/here', builder: (context, state) => screen),
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(body: Text('Homepage')),
            ),
            GoRoute(
              path: '/login',
              builder: (context, state) => const Scaffold(body: Text('Login')),
            ),
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const Scaffold(body: Text('Dashboard')),
            ),
          ],
        ),
      ),
    );
  }

  group('the 404 page', () {
    testWidgets('says what happened without blaming the reader', (tester) async {
      await tester.pumpWidget(wrap(const NotFoundScreen(location: '/nonsense')));
      await tester.pumpAndSettle();

      expect(find.text('Error 404'), findsOneWidget);
      expect(find.text("We couldn't find that page."), findsOneWidget);
      expect(find.textContaining('nothing has been lost'), findsOneWidget);
      // The brand, so it reads as the product rather than as a server error.
      expect(find.text('School365ai'), findsOneWidget);
    });

    testWidgets('shows the address that did not match', (tester) async {
      await tester.pumpWidget(wrap(const NotFoundScreen(location: '/studnets')));
      await tester.pumpAndSettle();

      expect(find.text('/studnets'), findsOneWidget);
    });

    testWidgets('offers a signed-out visitor the homepage and a way to sign in', (tester) async {
      await tester.pumpWidget(wrap(const NotFoundScreen(location: '/nonsense')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Go to School365ai'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign in'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Go to School365ai'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });

    testWidgets('offers a signed-in user their dashboard instead', (tester) async {
      await tester.pumpWidget(wrap(const NotFoundScreen(location: '/nonsense'), session: _teacher));
      await tester.pumpAndSettle();

      // "Sign in" would be a second dead end for somebody already signed in.
      expect(find.widgetWithText(OutlinedButton, 'Sign in'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Back to dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
    });
  });

  group('the maintenance page', () {
    testWidgets('explains the window and promises nothing was lost', (tester) async {
      await tester.pumpWidget(wrap(const MaintenanceScreen(), maintenance: () => _FakeMaintenance(comesBack: false)));
      await tester.pumpAndSettle();

      expect(find.text('Scheduled maintenance'), findsOneWidget);
      expect(find.text("We're making School365ai better."), findsOneWidget);
      expect(find.textContaining('Nothing has been lost'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('a check that finds it still down says so and stays put', (tester) async {
      final fake = _FakeMaintenance(comesBack: false);

      await tester.pumpWidget(wrap(const MaintenanceScreen(), maintenance: () => fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(fake.rechecks, 1);
      expect(find.textContaining('Still offline as of a moment ago'), findsOneWidget);
      expect(find.text("We're making School365ai better."), findsOneWidget);
    });

    testWidgets('a check that finds it back moves a signed-out visitor on', (tester) async {
      await tester.pumpWidget(wrap(const MaintenanceScreen(), maintenance: () => _FakeMaintenance(comesBack: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });

    testWidgets('a check that finds it back returns a signed-in user to their dashboard', (tester) async {
      await tester.pumpWidget(
        wrap(const MaintenanceScreen(), session: _teacher, maintenance: () => _FakeMaintenance(comesBack: true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('the button cannot be pressed twice while a check is running', (tester) async {
      final gate = Completer<void>();
      final fake = _FakeMaintenance(comesBack: false, gate: gate);

      await tester.pumpWidget(wrap(const MaintenanceScreen(), maintenance: () => fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // A second tap while it is in flight must not start a second check.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(fake.rechecks, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('both pages', () {
    for (final width in [360.0, 768.0, 1440.0]) {
      testWidgets('lay out without overflowing at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(wrap(const NotFoundScreen(location: '/a/very/long/path/that/does/not/exist')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(wrap(const MaintenanceScreen(), maintenance: () => _FakeMaintenance(comesBack: false)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
