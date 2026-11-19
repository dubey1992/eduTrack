import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/network/dio_client.dart';
import 'core/routing/family_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'features/family/application/family_session_notifier.dart';
import 'features/family/presentation/family_frame.dart';
import 'features/family/presentation/family_push_registrar.dart';
import 'features/maps/data/maps_config.dart';

/// The app a parent installs: School365ai Family (docs/parent-student-app.md).
///
/// The fourth product from one codebase, beside the office on the web
/// (main.dart), the bus (main_driver.dart) and the staff app
/// (main_teacher.dart). Same theme family, network layer and widgets; its own
/// sign-in, its own router, and an Android application id of its own, so a
/// parent sees an app that asks for nothing but the internet and
/// notifications. Built with:
///
///     flutter build apk --flavor family --target lib/main_family.dart
void main() {
  Env.checkReleaseConfiguration();
  runApp(
    ProviderScope(
      overrides: [
        // A family account cannot reach the staff maps/config (F4).
        mapsConfigRepositoryProvider.overrideWith(
          (ref) => MapsConfigRepository(ref.watch(dioClientProvider), path: '/family/maps-config'),
        ),
      ],
      child: const FamilyApp(),
    ),
  );
}

class FamilyApp extends ConsumerWidget {
  const FamilyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'School365ai Family',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.familyLight(),
      darkTheme: AppTheme.familyDark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(familyRouterProvider),
      // No SelectionArea, as in the other phone apps: on a phone it claims
      // every long press. The Overlay gives snackbars a home above the router.
      builder: (context, child) => FamilyPushRegistrar(
        // A tab is gone to; anything else opens over the tabs, as from Home.
        onOpen: (route) => FamilyPlace.values.any((place) => place.path == route)
            ? ref.read(familyRouterProvider).go(route)
            : ref.read(familyRouterProvider).push(route),
        child: AppLockGate(
          signedIn: ref.watch(familySessionProvider).value != null,
          child: Overlay(initialEntries: [OverlayEntry(builder: (context) => child ?? const SizedBox.shrink())]),
        ),
      ),
    );
  }
}
