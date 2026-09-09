import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';

Widget wrap(UserRole role) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 1, name: 'Actor', email: 'actor@example.com', role: role),
        ),
      ),
    ],
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

/// The sidebar's ListView only mounts elements within the viewport + cache
/// extent (true of every Sliver-based scrollable, not just .builder ones) -
/// the default 800x600 test surface is too short to fit every group as the
/// nav grows, which would silently make find.text() miss items further down
/// without this. Tall enough for the sidebar to render in full.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a super admin sees Schools, Payments, Users, Teachers & Staff and Students', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.superAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Schools'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Admin Users'), findsOneWidget);
    expect(find.text('Teachers & Staff'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
  });

  testWidgets('a school admin sees Users, Teachers & Staff and Students but not Schools or Payments', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Admin Users'), findsOneWidget);
    expect(find.text('Teachers & Staff'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Schools'), findsNothing);
    expect(find.text('Payments'), findsNothing);
  });

  testWidgets('a teacher sees Academics and Students but not Administration or Teachers & Staff', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.teacher));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Academic Years'), findsOneWidget);
    expect(find.text('Departments'), findsOneWidget);
    expect(find.text('Subjects'), findsOneWidget);
    expect(find.text('Classes & Sections'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Admin Users'), findsNothing);
    expect(find.text('Schools'), findsNothing);
    expect(find.text('Payments'), findsNothing);
    expect(find.text('Teachers & Staff'), findsNothing);
  });

  testWidgets('a staff member does not see Students', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.staff));
    await tester.pumpAndSettle();

    expect(find.text('Students'), findsNothing);
  });

  testWidgets('a staff member sees Staff Leave but not Staff Attendance', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.staff));
    await tester.pumpAndSettle();

    expect(find.text('Staff Leave'), findsOneWidget);
    expect(find.text('Staff Attendance'), findsNothing);
  });

  testWidgets('an hod sees both Staff Attendance and Staff Leave', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.hod));
    await tester.pumpAndSettle();

    expect(find.text('Staff Attendance'), findsOneWidget);
    expect(find.text('Staff Leave'), findsOneWidget);
  });

  testWidgets('a teacher sees Timetable under Academics', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(wrap(UserRole.teacher));
    await tester.pumpAndSettle();

    expect(find.text('Timetable'), findsOneWidget);
  });
}
