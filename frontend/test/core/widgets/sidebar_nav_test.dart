import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';

AuthenticatedUser _user(UserRole role, {int? schoolId, String? schoolName}) => AuthenticatedUser(
  id: 1,
  name: 'Actor',
  email: 'actor@example.com',
  role: role,
  schoolId: schoolId,
  schoolName: schoolName,
);

/// Every screen the menu offers [role], whichever area it sits in.
Set<String> _offered(UserRole role) {
  final user = _user(role);
  return {
    for (final group in AppNav.groupsFor(user))
      for (final item in group.itemsFor(user)) item.label,
  };
}

/// The menu on a page of its own, starting at [start]; every screen of the
/// app is a route, so opening an area really navigates.
Widget _menu(
  UserRole role, {
  String start = '/dashboard',
  bool inDrawer = false,
  AuthenticatedUser? user,
  KeyValueStore? store,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: user ?? _user(role))),
      keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: GoRouter(
        initialLocation: start,
        routes: [
          for (final item in AppNav.allItems)
            GoRoute(
              path: item.path,
              builder: (context, state) => Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (inDrawer) SizedBox(width: 304, child: SidebarNav(inDrawer: inDrawer)) else const SidebarNav(),
                    // The fold button lives in the shell's top bar.
                    Expanded(
                      child: Column(
                        children: [
                          const NavPanelToggle(),
                          Expanded(child: Center(child: Text('Page ${item.path}'))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Finder _inPanel(String label) => find.descendant(of: find.byKey(const Key('nav-panel')), matching: find.text(label));

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('who is offered what', () {
    // The same rules as before the menu became areas (2026-11-06): each
    // screen keeps its own access rule, wherever it now sits.
    test('a super admin has Schools, Payments, Users, Teachers & Staff and Students', () {
      expect(
        _offered(UserRole.superAdmin),
        containsAll(['Schools', 'Payments', 'Admin Users', 'Teachers & Staff', 'Students']),
      );
    });

    test('a school admin has Users, Teachers & Staff and Students but not Schools or Payments', () {
      final offered = _offered(UserRole.schoolAdmin);

      expect(offered, containsAll(['Admin Users', 'Teachers & Staff', 'Students']));
      expect(offered, isNot(contains('Schools')));
      expect(offered, isNot(contains('Payments')));
    });

    test('a teacher has the academic screens and Students, but no administration or Teachers & Staff', () {
      final offered = _offered(UserRole.teacher);

      expect(offered, containsAll(['Dashboard', 'Academic Years', 'Departments', 'Subjects', 'Classes & Sections']));
      expect(offered, containsAll(['Students', 'Timetable']));
      for (final label in ['Admin Users', 'Schools', 'Payments', 'Teachers & Staff']) {
        expect(offered, isNot(contains(label)), reason: label);
      }
    });

    test('a staff member has Staff Leave, and neither Students nor Staff Attendance', () {
      final offered = _offered(UserRole.staff);

      expect(offered, contains('Staff Leave'));
      expect(offered, isNot(contains('Students')));
      expect(offered, isNot(contains('Staff Attendance')));
    });

    test('an accountant has what every employee has, plus Reports, and nothing of admin or teaching', () {
      final offered = _offered(UserRole.accountant);

      for (final label in ['Dashboard', 'Reports', 'Staff Leave', 'My Inbox', 'Timetable']) {
        expect(offered, contains(label), reason: '$label is for every employee');
      }
      for (final label in [
        'Students',
        'Student Attendance',
        'Staff Attendance',
        'Teachers & Staff',
        'Trips',
        'Payments',
      ]) {
        expect(offered, isNot(contains(label)), reason: '$label is not for an accountant');
      }
    });

    for (final (role, payroll, payslips) in [
      (UserRole.accountant, true, true),
      (UserRole.schoolAdmin, true, true),
      (UserRole.groupAdmin, true, true),
      (UserRole.superAdmin, true, false),
      (UserRole.teacher, false, true),
      (UserRole.hod, false, true),
      (UserRole.transportManager, false, true),
      (UserRole.staff, false, true),
    ]) {
      test('payroll for a ${role.label}', () {
        expect(_offered(role).contains('Payroll'), payroll);
        expect(_offered(role).contains('My Payslips'), payslips);
      });
    }

    for (final (role, auditLog) in [
      (UserRole.superAdmin, true),
      (UserRole.groupAdmin, true),
      (UserRole.schoolAdmin, true),
      (UserRole.hod, false),
      (UserRole.teacher, false),
      (UserRole.staff, false),
      (UserRole.transportManager, false),
      (UserRole.accountant, false),
    ]) {
      test('audit log for a ${role.label}', () {
        expect(_offered(role).contains('Audit Log'), auditLog);
      });
    }

    test('an hod has both Staff Attendance and Staff Leave', () {
      expect(_offered(UserRole.hod), containsAll(['Staff Attendance', 'Staff Leave']));
    });
  });

  group('the areas', () {
    test('every screen of the menu sits in exactly one area', () {
      final paths = [for (final group in AppNav.groups) ...group.items.map((item) => item.path)];

      expect(paths.toSet(), hasLength(paths.length));
    });

    test('related screens sit together', () {
      expect(AppNav.groupOf('/fee-receipts')!.label, 'Fees');
      expect(AppNav.groupOf('/leaves')!.label, 'Attendance');
      expect(AppNav.groupOf('/timetable')!.label, 'Teaching');
      expect(AppNav.groupOf('/transport/drivers')!.label, 'Transport');
      expect(AppNav.groupOf('/profile'), isNull);
    });

    test('a role sees only the areas it has a screen in', () {
      final teacher = AppNav.groupsFor(_user(UserRole.teacher)).map((group) => group.label);

      expect(teacher, containsAll(['Dashboard', 'People', 'Attendance', 'Teaching', 'Academic Setup', 'Messages']));
      expect(teacher, isNot(contains('Fees')));
      expect(teacher, isNot(contains('Settings')));
      expect(teacher, isNot(contains('Schools')));
    });

    test("a teacher's Payroll area holds only their own payslips", () {
      final teacher = _user(UserRole.teacher);

      expect(AppNav.payroll.itemsFor(teacher).map((item) => item.label), ['My Payslips']);
    });
  });

  group('the menu on screen', () {
    testWidgets("shows the strip of areas and the open page's area", (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin, start: '/attendance'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-area-Fees')), findsOneWidget);
      expect(find.byKey(const Key('nav-area-Schools')), findsNothing);
      expect(_inPanel('ATTENDANCE'), findsOneWidget);
      expect(_inPanel('Student Attendance'), findsOneWidget);
      expect(_inPanel('Staff Leave'), findsOneWidget);
      expect(_inPanel('Students'), findsNothing);
    });

    testWidgets("an area's icon opens its first screen", (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-area-Fees')));
      await tester.pumpAndSettle();

      expect(find.text('Page /student-fees'), findsOneWidget);
      expect(_inPanel('Receipts'), findsOneWidget);
    });

    testWidgets('the logo goes to the Dashboard', (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin, start: '/fee-receipts'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-logo')));
      await tester.pumpAndSettle();

      expect(find.text('Page /dashboard'), findsOneWidget);
    });

    testWidgets('a screen in the list opens it', (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin, start: '/student-fees'));
      await tester.pumpAndSettle();

      await tester.tap(_inPanel('Receipts'));
      await tester.pumpAndSettle();

      expect(find.text('Page /fee-receipts'), findsOneWidget);
    });

    testWidgets('the list folds away and comes back', (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-panel-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-panel')), findsNothing);
      expect(find.byKey(const Key('nav-area-Fees')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-panel-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-panel')), findsOneWidget);
    });

    testWidgets('folded away, an area pops up its screens and the panel stays folded', (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-panel-toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-area-Fees')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-flyout-/fee-receipts')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-flyout-/fee-receipts')));
      await tester.pumpAndSettle();

      expect(find.text('Page /fee-receipts'), findsOneWidget);
      expect(find.byKey(const Key('nav-panel')), findsNothing);
    });

    testWidgets('folded away, closing the pop-up without a pick stays on the page', (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-panel-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-area-Fees')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(1300, 1300));
      await tester.pumpAndSettle();

      expect(find.text('Page /dashboard'), findsOneWidget);
      expect(find.byKey(const Key('nav-flyout-/fee-receipts')), findsNothing);
    });

    testWidgets('folding is remembered on this device', (tester) async {
      _useDesktop(tester);
      final store = InMemoryKeyValueStore();
      await tester.pumpWidget(_menu(UserRole.schoolAdmin, store: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-panel-toggle')));
      await tester.pumpAndSettle();

      expect(await store.read('nav_panel_open'), 'false');
    });

    testWidgets('a folded panel stays folded when the app opens again', (tester) async {
      _useDesktop(tester);
      final store = InMemoryKeyValueStore();
      await store.write('nav_panel_open', 'false');

      await tester.pumpWidget(_menu(UserRole.schoolAdmin, store: store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-panel')), findsNothing);
      expect(find.byKey(const Key('nav-area-Fees')), findsOneWidget);
    });

    testWidgets("the school is not in the side panel - its logo and name are in the top bar since 2026-11-21", (
      tester,
    ) async {
      _useDesktop(tester);
      final teacher = _user(UserRole.teacher, schoolId: 7, schoolName: 'Riverside Public School');
      await tester.pumpWidget(_menu(UserRole.teacher, user: teacher));
      await tester.pumpAndSettle();

      expect(find.text('Riverside Public School'), findsNothing);
      expect(find.text('RP'), findsNothing);
      expect(find.text('School Management'), findsNothing);
    });

    testWidgets("a super admin, who has no school, sees the product's name", (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.superAdmin));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-school')), findsNothing);
      expect(find.text('School Management'), findsOneWidget);
    });

    testWidgets("in the phone's drawer an area shows its list without leaving the page", (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.schoolAdmin, inDrawer: true));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(SidebarNav), matching: find.byKey(const Key('nav-panel-toggle'))),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('nav-area-Fees')));
      await tester.pumpAndSettle();

      expect(find.text('Page /dashboard'), findsOneWidget);
      expect(_inPanel('Receipts'), findsOneWidget);

      await tester.tap(_inPanel('Receipts'));
      await tester.pumpAndSettle();

      expect(find.text('Page /fee-receipts'), findsOneWidget);
    });

    testWidgets('an area with nothing left for the user is not drawn', (tester) async {
      _useDesktop(tester);
      await tester.pumpWidget(_menu(UserRole.staff));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-area-Fees')), findsNothing);
      expect(find.byKey(const Key('nav-area-Settings')), findsNothing);
      expect(find.byKey(const Key('nav-area-Attendance')), findsOneWidget);
    });
  });
}
