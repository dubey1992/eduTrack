import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The steps every end-to-end workflow shares: a desktop-sized window, the
/// app from its landing page, signing in and out, and the sidebar.
///
/// The accounts come from the backend's fixtures, all with the password
/// "password":
///   cd backend-python && python manage.py integration_fixtures seed
/// Seed before each test file - several of them use something up (the one
/// pending leave, today's register, today's pickup trip).
const fixturePassword = 'password';

Future<void> startApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 3));

  // Marketing homepage (unauthenticated landing) -> Login screen.
  await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> login(WidgetTester tester, {required String email}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), fixturePassword);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

Future<void> logout(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Log out'));
  await tester.pumpAndSettle();

  // Logging out asks first (see app_shell.dart's _confirmLogout).
  await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Opens a page from the sidebar, scrolling to it first - a Super Admin's
/// sidebar is longer than the window, and a lazy list does not build what is
/// off screen.
Future<void> openPage(WidgetTester tester, String label) async {
  final sidebar = find.byType(SidebarNav);
  final item = find.descendant(of: sidebar, matching: find.text(label));

  await tester.scrollUntilVisible(
    item,
    120,
    scrollable: find.descendant(of: sidebar, matching: find.byType(Scrollable)).first,
  );
  // Let the scroll finish first: a tap aimed while the list is still moving
  // lands where the item was, and misses without failing.
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Picks an item from a labelled dropdown. The chosen text is built twice
/// while the menu is open - in the menu and behind it - so the menu's copy
/// is the last one.
Future<void> pickFromDropdown<T>(WidgetTester tester, String label, String item) async {
  // A long menu builds only what is on screen, so it is scrolled until the
  // item appears. The same text may already be elsewhere on the page (a table
  // row behind a dialog), so what is looked for is a copy that was not there
  // before the menu opened.
  final copiesBefore = find.text(item).evaluate().length;

  await tester.tap(find.widgetWithText(DropdownButtonFormField<T>, label));
  await tester.pumpAndSettle();

  final menu = find.byType(Scrollable).last;
  for (var i = 0; i < 60 && find.text(item).evaluate().length <= copiesBefore; i++) {
    await tester.drag(menu, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// A status badge by its label. Filter chips and KPI cards reuse words such
/// as "Pending", so find.text alone cannot tell them from a row's badge.
Finder statusBadge(String label) {
  return find.byWidgetPredicate((widget) => widget is StatusBadge && widget.label == label);
}
