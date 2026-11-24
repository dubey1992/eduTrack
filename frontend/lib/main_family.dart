import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/home_widget/home_screen_widget.dart';
import 'core/network/dio_client.dart';
import 'core/routing/family_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'features/family/application/family_session_notifier.dart';
import 'features/family/presentation/family_frame.dart';
import 'features/family/presentation/family_push_registrar.dart';
import 'features/home_widget/today_widget_background.dart';
import 'features/home_widget/today_widget_refresh.dart';
import 'features/home_widget/today_widget_sync.dart';
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
  WidgetsFlutterBinding.ensureInitialized();
  // The home-screen widget's half-hourly refresh (M10).
  initialiseTodayWidget();
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
        child: TodayWidgetSync(
          app: familyWidgetApp,
          signedIn: _signedIn(ref.watch(familySessionProvider)),
          // The widget is about the child last looked at; another child
          // picked is a new card.
          onChange: (ref, refresh) => ref.listen(selectedChildProvider, (_, _) => refresh()),
          beforeRefresh: (ref) async {
            final child = ref.read(selectedChildProvider);
            if (child == null) return;
            final widget = ref.read(homeScreenWidgetProvider);
            await widget.remember(widgetChildIdKey, '${child.id}');
            await widget.remember(widgetChildNameKey, child.firstName);
          },
          child: AppLockGate(
            signedIn: ref.watch(familySessionProvider).value != null,
            child: Overlay(initialEntries: [OverlayEntry(builder: (context) => child ?? const SizedBox.shrink())]),
          ),
        ),
      ),
    );
  }
}

/// Null while the session is still being read back at start-up.
bool? _signedIn(AsyncValue<Object?> session) => session.isLoading && !session.hasValue ? null : session.value != null;
