import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: EduTrackApp()));
}

class EduTrackApp extends ConsumerWidget {
  const EduTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'School365ai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      // Plain Text widgets aren't selectable by default in Flutter (true on
      // every platform, not just web) - without this, nothing on screen
      // (emails, IDs, names in tables/lists) can be selected or copied,
      // which is what was actually being reported as "can't copy anything".
      //
      // SelectionArea's selection handles need an Overlay ancestor, but
      // MaterialApp.router's builder wraps content *outside* the Navigator
      // (and its Overlay) that the app builds internally - so a plain
      // SelectionArea here throws "No Overlay widget found". Giving it its
      // own Overlay first is the documented workaround for that ordering.
      builder: (context, child) => Overlay(
        initialEntries: [OverlayEntry(builder: (context) => SelectionArea(child: child ?? const SizedBox.shrink()))],
      ),
    );
  }
}
