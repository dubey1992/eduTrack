import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The steps every end-to-end workflow shares: a desktop-sized window, the
/// app from its landing page, signing in and out, and the menu.
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

/// Opens a page from the menu the way a person does: the area's icon in
/// the strip, then the screen in its list (docs/navigation-tabs.md, S2).
Future<void> openPage(WidgetTester tester, String label) async {
  final item = await _findInMenu(tester, label);
  if (item == null) fail('The menu does not offer "$label".');

  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Whether the menu offers a screen, looked for the way a person looks:
/// each area that could hold it, opened in turn. Opening an area opens its
/// first screen, so the page the flow was on is opened again afterwards.
Future<bool> sidebarShows(WidgetTester tester, String label) async {
  final router = GoRouter.of(tester.element(find.byType(SidebarNav)));
  final startedOn = router.routerDelegate.currentConfiguration.uri.toString();

  final shown = await _findInMenu(tester, label) != null;

  if (router.routerDelegate.currentConfiguration.uri.toString() != startedOn) {
    router.go(startedOn);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  return shown;
}

/// The screen [label] in the menu's list, after opening the area it is in,
/// or null when no area the user has offers it.
Future<Finder?> _findInMenu(WidgetTester tester, String label) async {
  for (final group in AppNav.groups.where((group) => group.items.any((item) => item.label == label))) {
    final area = find.byKey(Key('nav-area-${group.label}'));
    if (area.evaluate().isEmpty) continue;

    await tester.tap(area);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final item = find.descendant(of: find.byKey(const Key('nav-panel')), matching: find.text(label));
    if (item.evaluate().isNotEmpty) return item;
  }

  return null;
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

/// The one of [candidates] sitting on the same line as [anchor].
///
/// A table's rows are configuration rather than widgets, so there is no row
/// to search inside: the control belonging to a row is the one level with
/// its text, which is how a person finds it too. Needed wherever a table
/// repeats a control down a column - every "Terms", every "Submit Report" -
/// and the row is the only thing telling them apart.
Finder onSameLineAs(WidgetTester tester, Finder anchor, Finder candidates) {
  expect(anchor, findsWidgets, reason: 'there is nothing to line up against');
  expect(candidates, findsWidgets, reason: 'there is nothing to choose from');

  final line = tester.getCenter(anchor.first).dy;

  var nearest = candidates.at(0);
  var distance = double.infinity;

  for (var index = 0; index < candidates.evaluate().length; index++) {
    final gap = (tester.getCenter(candidates.at(index)).dy - line).abs();

    if (gap < distance) {
      distance = gap;
      nearest = candidates.at(index);
    }
  }

  return nearest;
}

/// A status badge by its label. Filter chips and KPI cards reuse words such
/// as "Pending", so find.text alone cannot tell them from a row's badge.
Finder statusBadge(String label) {
  return find.byWidgetPredicate((widget) => widget is StatusBadge && widget.label == label);
}
