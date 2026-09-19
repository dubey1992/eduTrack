import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/routing/app_router.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/session_users.dart';

NavItem _item(String path) => AppNav.findByPath(path)!;

/// The sidebar alone, for one signed-in user.
Widget _sidebarFor(AuthenticatedUser user) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: user))],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: SidebarNav()),
          ),
        ],
      ),
    ),
  );
}

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('a module item', () {
    test('is hidden when the school has the module switched off, whatever the level', () {
      final teacher = sessionUser(
        UserRole.teacher,
        permissions: allModulesAt(PermissionLevel.manage),
        modules: {AppModules.attendance: false},
      );

      expect(_item('/attendance').allows(teacher), isFalse);
      // The switch is per module, not per person.
      expect(_item('/students').allows(teacher), isTrue);
    });

    test('is hidden when the matrix gives the role none', () {
      final teacher = sessionUser(UserRole.teacher, permissions: {AppModules.students: PermissionLevel.none});

      expect(_item('/students').allows(teacher), isFalse);
    });

    test('shows on view, and the matrix outranks the role set the screen was built with', () {
      // Teachers & Staff was admin-only; a teacher raised to view sees it.
      final teacher = sessionUser(UserRole.teacher, permissions: {AppModules.staff: PermissionLevel.view});

      expect(_item('/staff').allows(teacher), isTrue);
    });

    test('a manage item stays hidden on view', () {
      final admin = sessionUser(UserRole.schoolAdmin, permissions: allModulesAt(PermissionLevel.view));

      expect(_item('/payroll').allows(admin), isFalse);
      expect(_item('/communication').allows(admin), isFalse);
      // The view items still show.
      expect(_item('/students').allows(admin), isTrue);
    });

    test('every academics screen follows the one academics module', () {
      final staff = sessionUser(UserRole.staff, permissions: {AppModules.academics: PermissionLevel.none});

      for (final path in ['/academic-years', '/holidays', '/departments', '/subjects', '/classes']) {
        expect(_item(path).allows(staff), isFalse, reason: path);
      }
    });

    test('every transport screen follows the one transport module', () {
      final hod = sessionUser(UserRole.hod, modules: {AppModules.transport: false});

      for (final path in ['/transport/vehicles', '/transport/drivers', '/transport/routes', '/transport/trips']) {
        expect(_item(path).allows(hod), isFalse, reason: path);
      }
    });

    test('with no matrix in the session keeps the role set it always had', () {
      // A teacher's default on reports is view, but the screen has no report
      // for them and the sidebar never offered it; a role-only session
      // changes nothing.
      expect(_item('/reports').allows(sessionUser(UserRole.teacher)), isFalse);
      expect(_item('/reports').allows(sessionUser(UserRole.hod)), isTrue);
      expect(_item('/students').allows(sessionUser(UserRole.staff)), isFalse);
      expect(_item('/attendance').allows(sessionUser(UserRole.teacher)), isTrue);
    });

    test('with no matrix still honours the module switches', () {
      expect(
        _item('/attendance').allows(sessionUser(UserRole.teacher, modules: {AppModules.attendance: false})),
        isFalse,
      );
    });
  });

  group('My Payslips', () {
    test('asks no level of payroll - it is everybody\'s own payslips', () {
      final teacher = sessionUser(UserRole.teacher, permissions: {AppModules.payroll: PermissionLevel.none});

      expect(_item('/my-payslips').allows(teacher), isTrue);
      expect(_item('/payroll').allows(teacher), isFalse);
    });

    test('goes with the payroll module', () {
      final teacher = sessionUser(UserRole.teacher, modules: {AppModules.payroll: false});

      expect(_item('/my-payslips').allows(teacher), isFalse);
    });

    test('is never the Super Admin\'s, who is employed by no school', () {
      expect(_item('/my-payslips').allows(sessionUser(UserRole.superAdmin)), isFalse);
    });
  });

  group('a role-gated item', () {
    test('ignores the matrix and the switches', () {
      final admin = sessionUser(
        UserRole.schoolAdmin,
        permissions: allModulesAt(PermissionLevel.none),
        modules: {for (final module in allModules) module: false},
      );

      for (final path in ['/dashboard', '/inbox', '/users', '/audit-log', '/module-settings', '/permissions']) {
        expect(_item(path).allows(admin), isTrue, reason: path);
      }
      for (final path in ['/schools', '/payments', '/early-access', '/mail-settings']) {
        expect(_item(path).allows(admin), isFalse, reason: '$path is the platform\'s own');
      }
    });

    test('Module Settings and Permissions are for the administrators', () {
      for (final path in ['/module-settings', '/permissions']) {
        for (final role in [UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin]) {
          expect(_item(path).allows(sessionUser(role)), isTrue, reason: '$path for ${role.label}');
        }
        for (final role in [
          UserRole.hod,
          UserRole.teacher,
          UserRole.staff,
          UserRole.transportManager,
          UserRole.accountant,
        ]) {
          expect(_item(path).allows(sessionUser(role)), isFalse, reason: '$path for ${role.label}');
        }
      }
    });
  });

  group('the sidebar', () {
    testWidgets('does not offer Student Attendance to a teacher whose school has it off', (tester) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(_sidebarFor(sessionUser(UserRole.teacher, modules: {AppModules.attendance: false})));
      await tester.pumpAndSettle();

      expect(find.text('Student Attendance'), findsNothing);
      // The rest of the group is still there.
      expect(find.text('Staff Leave'), findsOneWidget);
    });

    testWidgets('does not offer a module the matrix gives the role none on', (tester) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(
        _sidebarFor(sessionUser(UserRole.teacher, permissions: {AppModules.students: PermissionLevel.none})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Students'), findsNothing);
    });

    testWidgets('drops a whole group when nothing in it is left', (tester) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(_sidebarFor(sessionUser(UserRole.hod, modules: {AppModules.transport: false})));
      await tester.pumpAndSettle();

      expect(find.text('TRANSPORT'), findsNothing);
      expect(find.text('Vehicles'), findsNothing);
    });
  });

  group('the router', () {
    testWidgets('sends a switched-off module\'s route back to the dashboard', (tester) async {
      _useDesktopViewport(tester);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              sessionOnRestore: sessionUser(UserRole.teacher, modules: {AppModules.attendance: false}),
            ),
          ),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EduTrackApp()));
      await tester.pumpAndSettle();

      container.read(routerProvider).go('/attendance');
      await tester.pumpAndSettle();

      expect(find.text('Daily class attendance register'), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('sends a route the matrix denies back to the dashboard', (tester) async {
      _useDesktopViewport(tester);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              sessionOnRestore: sessionUser(UserRole.teacher, permissions: {AppModules.students: PermissionLevel.none}),
            ),
          ),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EduTrackApp()));
      await tester.pumpAndSettle();

      container.read(routerProvider).go('/students');
      await tester.pumpAndSettle();

      expect(find.text('Student Management'), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
    });
  });
}
