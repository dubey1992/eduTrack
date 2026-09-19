import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/module_settings/presentation/module_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Admin: login -> Module Settings -> switch Syllabus off -> the sidebar
/// drops it -> switch it back on, end to end against a real backend
/// (docs/settings.md). The switch goes through the API, the API changes what
/// /me answers, and the sidebar follows - so this checks the whole loop, not
/// just the screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a school admin switches a module off and on and the sidebar follows', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');

    expect(sidebarEntry('Syllabus'), findsOneWidget);

    await openPage(tester, 'Module Settings');
    expect(find.text('Module Settings'), findsWidgets);

    // The page's own scrollable, not the sidebar's.
    final page = find.descendant(of: find.byType(ModuleSettingsScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('module-school-syllabus')), 200, scrollable: page);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-school-syllabus')));
    await tester.pumpAndSettle();

    expect(find.text('Switch off Syllabus?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Switch off'));
    await waitFor(tester, find.text('Off'));

    expect(sidebarEntry('Syllabus'), findsNothing);

    // Back on: no confirmation, and the entry returns.
    await tester.tap(find.byKey(const Key('module-school-syllabus')));
    await waitFor(tester, sidebarEntry('Syllabus'));
  });
}

Finder sidebarEntry(String label) => find.descendant(of: find.byType(SidebarNav), matching: find.text(label));

/// Pumps until [finder] matches, giving a real request time to answer.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(finder, findsWidgets);
}
