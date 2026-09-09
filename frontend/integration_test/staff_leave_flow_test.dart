import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end regression for Phase 9: drives the REAL compiled app (no
/// mocked repositories) against the REAL Laravel backend at
/// http://localhost:8000, in a real visible browser window - this is the
/// only test in the project that actually proves the UI renders and the
/// full stack talks to itself correctly, rather than trusting isolated
/// widget/unit tests.
///
/// Requires the backend dev server running (`php artisan serve`) and two
/// fixture users already seeded in that same database - a Teacher and the
/// HOD of their department, both with password "password":
///   itest-teacher@example.com, itest-hod@example.com
/// See backend/tests/Support/seed_staff_leave_fixtures.php for the seed/
/// clean script that creates and tears these down. Run with:
///   flutter test integration_test/staff_leave_flow_test.dart -d chrome
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const teacherEmail = 'itest-teacher@example.com';
  const hodEmail = 'itest-hod@example.com';
  const password = 'password';

  Future<void> useWideWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> login(WidgetTester tester, {required String email}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  Future<void> logout(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  // The status filter row always renders a "Pending"/"Approved" chip
  // regardless of data, so find.text() alone can't tell a filter chip
  // from the leave's own status badge - this targets the badge specifically.
  Finder statusBadge(String label) {
    return find.byWidgetPredicate((widget) => widget is StatusBadge && widget.label == label);
  }

  testWidgets('a teacher applies for leave and an HOD approves it, syncing attendance', (tester) async {
    await useWideWindow(tester);

    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Marketing homepage (unauthenticated landing) -> Login screen.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---- Teacher applies for leave ----
    await login(tester, email: teacherEmail);
    expect(find.text('Dashboard'), findsWidgets);

    await tester.tap(find.text('Staff Leave'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Apply Leave'));
    await tester.pumpAndSettle();

    // Leave type stays at the default (Casual), From/To stay at today - a
    // valid single-day request - only the required reason needs filling in.
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Integration test leave request');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit Request'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Leave request submitted.'), findsOneWidget);
    expect(statusBadge('Pending'), findsOneWidget);

    await logout(tester);

    // ---- HOD reviews and approves it ----
    await login(tester, email: hodEmail);

    await tester.tap(find.text('Staff Leave'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Leave request approved.'), findsOneWidget);
    expect(statusBadge('Approved'), findsOneWidget);
    expect(statusBadge('Pending'), findsNothing);
  });
}
