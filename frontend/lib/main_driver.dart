import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/driver_router.dart';
import 'core/theme/app_theme.dart';

/// The app the bus crew installs (docs/driver-app.md).
///
/// Same codebase as the school's web app, same theme, same API - and a
/// different product. `main.dart` serves the office, which is twenty
/// modules behind a marketing homepage; this serves a phone in a cradle,
/// which has one job. Built with:
///
///     flutter build apk --target lib/main_driver.dart
///
/// The two differ only in the router they hand to MaterialApp: everything
/// below that - the theme, the network layer, the auth notifier, the trip
/// screen itself - is the same code, which is the whole reason the driver
/// app is a day's work rather than a second project.
void main() {
  runApp(const ProviderScope(child: DriverApp()));
}

class DriverApp extends ConsumerWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'School365ai Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(driverRouterProvider),
      // **No SelectionArea here**, unlike the web app.
      //
      // The portal has one so an administrator can copy a phone number off
      // a screen. On the bus nobody copies anything, and the cost is real:
      // it claims every long press, so holding the SOS button highlighted
      // the label and opened a Copy bar instead of calling for help, and a
      // hold that reaches past a scroll leaves a selection behind. A
      // feature nobody on a bus uses is not worth a gesture they do
      // (docs/driver-app.md, D5.2).
      //
      // The Overlay stays: MaterialApp.router's builder wraps content
      // outside the Navigator's own, and things that need one (a snackbar
      // from a page, for instance) find it here.
      builder: (context, child) =>
          Overlay(initialEntries: [OverlayEntry(builder: (context) => child ?? const SizedBox.shrink())]),
    );
  }
}
