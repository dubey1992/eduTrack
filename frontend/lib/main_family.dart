import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/network/dio_client.dart';
import 'core/routing/family_router.dart';
import 'core/theme/app_theme.dart';
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
        onOpenNotices: () => ref.read(familyRouterProvider).push('/notices'),
        child: Overlay(initialEntries: [OverlayEntry(builder: (context) => child ?? const SizedBox.shrink())]),
      ),
    );
  }
}
