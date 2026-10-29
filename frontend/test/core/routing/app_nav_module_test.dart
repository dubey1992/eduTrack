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
  group('Fee Setup (docs/fees.md)', () {
    test('needs the module switched on for the school', () {
      final accountant = sessionUser(UserRole.accountant, modules: {AppModules.fees: false});

      expect(_item('/fee-setup').allows(accountant), isFalse);
    });

    test('belongs to the admin and the accountant out of the box, and nobody else', () {
      final on = {AppModules.fees: true};

      expect(_item('/fee-setup').allows(sessionUser(UserRole.schoolAdmin, modules: on)), isTrue);
      expect(_item('/fee-setup').allows(sessionUser(UserRole.accountant, modules: on)), isTrue);
      expect(_item('/fee-setup').allows(sessionUser(UserRole.teacher, modules: on)), isFalse);
      expect(_item('/fee-setup').allows(sessionUser(UserRole.hod, modules: on)), isFalse);
    });

    test('without a matrix in the session, falls back to the same two roles', () {
      expect(
        _item('/fee-setup').allows(const AuthenticatedUser(id: 1, name: 'T', email: 't@x.com', role: UserRole.teacher)),
        isFalse,
      );
      expect(
        _item('/fee-setup')
            .allows(const AuthenticatedUser(id: 1, name: 'A', email: 'a@x.com', role: UserRole.accountant)),
        isTrue,
      );
    });

    test('follows the matrix when a school widens it', () {
      final clerk = sessionUser(
        UserRole.staff,
        permissions: {AppModules.fees: PermissionLevel.manage},
        modules: {AppModules.fees: true},
      );

      expect(_item('/fee-setup').allows(clerk), isTrue);
    });
  });

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

    test('analytics follows reports, except for a role it has no chart for yet', () {
      final reader = {AppModules.reports: PermissionLevel.view};

      expect(_item('/analytics').allows(sessionUser(UserRole.schoolAdmin, permissions: reader)), isTrue);
      expect(_item('/analytics').allows(sessionUser(UserRole.accountant, permissions: reader)), isTrue);
      // Reads reports, but its charts are A6's (docs/analytics.md).
      expect(_item('/analytics').allows(sessionUser(UserRole.transportManager, permissions: reader)), isFalse);
      expect(
        _item('/analytics')
            .allows(sessionUser(UserRole.schoolAdmin, permissions: {AppModules.reports: PermissionLevel.none})),
        isFalse,
      );
      expect(_item('/analytics').allows(sessionUser(UserRole.teacher)), isFalse);
      expect(
        _item('/analytics').allows(sessionUser(UserRole.schoolAdmin, modules: {AppModules.reports: false})),
        isFalse,
      );
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

  group('Class Promotion', () {
    test('belongs to an administrator, not to a teacher or a head', () {
      expect(_item('/promotion').allows(sessionUser(UserRole.schoolAdmin)), isTrue);
      expect(_item('/promotion').allows(sessionUser(UserRole.groupAdmin)), isTrue);
      expect(_item('/promotion').allows(sessionUser(UserRole.teacher)), isFalse);
      expect(_item('/promotion').allows(sessionUser(UserRole.hod)), isFalse);
    });

    test("is never the Super Admin's, whatever the matrix grants them", () {
      // They are full on every module by definition, so only the denial
      // keeps them out - and the API refuses them too (docs/promotion.md).
      expect(
        _item('/promotion').allows(sessionUser(UserRole.superAdmin, permissions: allModulesAt(PermissionLevel.manage))),
        isFalse,
      );
    });

    test('needs manage on academics, not just a look at it', () {
      final reader = sessionUser(UserRole.schoolAdmin, permissions: {AppModules.academics: PermissionLevel.view});

      expect(_item('/promotion').allows(reader), isFalse);
    });

    test('goes with the academics module', () {
      final admin = sessionUser(UserRole.schoolAdmin, modules: {AppModules.academics: false});

      expect(_item('/promotion').allows(admin), isFalse);
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
      for (final path in ['/schools', '/payments', '/early-access', '/demo-requests', '/mail-settings']) {
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

  group('biometric, the module a school asks for', () {
    // Unlike every other module it arrives off, so the sidebar entry is
    // absent until somebody switches it on (docs/biometric.md).
    test('the entry is hidden while the module is off', () {
      expect(
        _item('/biometric-devices').allows(sessionUser(UserRole.schoolAdmin, modules: {AppModules.biometric: false})),
        isFalse,
      );
    });

    test('and shown once it is on', () {
      expect(
        _item('/biometric-devices').allows(sessionUser(UserRole.schoolAdmin, modules: {AppModules.biometric: true})),
        isTrue,
      );
    });

    test('switching it off leaves the staff register alone', () {
      // The register is a school's own record; a module switch takes a
      // screen away, it does not take attendance away.
      final admin = sessionUser(UserRole.schoolAdmin, modules: {AppModules.biometric: false});

      expect(_item('/staff-attendance').allows(admin), isTrue);
    });

    test('an HOD never gets it, even switched on', () {
      // They mark the staff register; they do not buy the readers.
      expect(
        _item('/biometric-devices').allows(sessionUser(UserRole.hod, modules: {AppModules.biometric: true})),
        isFalse,
      );
    });
  });
}
