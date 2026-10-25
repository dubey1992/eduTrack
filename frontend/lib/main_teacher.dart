import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/teacher_router.dart';
import 'core/theme/app_theme.dart';

/// The app a teacher installs (docs/teacher-app.md).
///
/// The third product from one codebase. `main.dart` is the office on the
/// web; `main_driver.dart` is the phone on the bus; this is the phone in a
/// teacher's hand between periods. Same theme, same network layer, same
/// auth, same repositories - a different router, and a different Android
/// application id so that Play, and a cautious school, see an app that asks
/// for nothing a teacher does not need. Built with:
///
///     flutter build apk --flavor teacher --target lib/main_teacher.dart
void main() {
  runApp(const ProviderScope(child: TeacherApp()));
}

class TeacherApp extends ConsumerWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'School365ai',
      debugShowCheckedModeBanner: false,
      // The portal's theme in the teacher brand's teal (core/theme/teacher_brand.dart).
      theme: AppTheme.teacherLight(),
      darkTheme: AppTheme.teacherDark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(teacherRouterProvider),
      // No SelectionArea, for the same reasons the driver app has none
      // (main_driver.dart): on a phone it claims every long press and
      // leaves selections behind scrolls, and nobody copies text off a
      // register. The Overlay stays so snackbars from pages have a home.
      builder: (context, child) =>
          Overlay(initialEntries: [OverlayEntry(builder: (context) => child ?? const SizedBox.shrink())]),
    );
  }
}
